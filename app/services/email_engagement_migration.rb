# frozen_string_literal: true

require "aws-sdk-dynamodb"
require "digest"
require "json"
require_relative "email_engagement_migration_projection"

class EmailEngagementMigration
  CONTROL_KEY = { "pk" => "__email_engagement_migration__", "sk" => "CONTROL" }.freeze
  FORMAT_VERSION = 1
  MAX_ATTEMPTS = 6
  RETRYABLE_ERRORS = %w[InternalServerError ProvisionedThroughputExceededException RequestLimitExceeded ThrottlingException].freeze

  class UnsafeTarget < StandardError; end
  class ReconciliationFailed < StandardError; end

  def initialize(source:, client:, table_name:, active_table_name:, run_id:, snapshot_id:,
                 source_frozen: false, target_isolated: false, sleeper: Kernel.method(:sleep))
    unless source_frozen && target_isolated && !active_table_name.to_s.empty? && table_name != active_table_name
      raise UnsafeTarget, "Use a frozen source and an isolated, empty staging table different from the active runtime table; concurrent target writes are unsupported"
    end
    [table_name, run_id, snapshot_id].each do |value|
      raise ArgumentError, "Table, run and snapshot identifiers are required" unless value.is_a?(String) && !value.empty?
    end
    @source, @client, @table_name = source, client, table_name
    @run_id, @snapshot_id, @sleeper = run_id, snapshot_id, sleeper
  end

  def import!
    @source.validate!
    control = claim_target!
    raise UnsafeTarget, "Released tables cannot be imported again" if control["state"] == "released"
    return reconcile! if control["state"] == "reconciled"

    # Dynamo numeric attributes decode as BigDecimal, which is not a Mongo integer cursor.
    cursor = control.fetch("last_partition")
    unless cursor.is_a?(Numeric) && cursor >= 0 && cursor == cursor.to_i
      raise UnsafeTarget, "Invalid partition checkpoint"
    end
    @source.each_partition(after: cursor.to_i) do |id|
      projected_items(id).each { |item| insert_immutable!(item) }
      # Only a fully written partition advances the cursor; a lost response rechecks exact items.
      control = replace_control!(control, control.merge("last_partition" => id))
    end
    report = reconcile!
    replace_control!(control, control.merge("state" => "reconciled", "report" => report))
    report
  end

  def reconcile!
    @source.validate!
    control = owned_control!
    partitions = 0
    item_count = 0
    totals = { "open_count" => 0, "click_count" => 0, "click_pair_count" => 0, "repeat_open_count" => 0 }
    fingerprint = Digest::SHA256.new
    # Never trust import checkpoints or legacy Mongo summary documents during reconciliation.
    @source.each_partition do |id|
      expected = projected_items(id)
      actual = query_partition(id)
      unless actual.sort_by { |item| item.fetch("sk") } == expected
        raise ReconciliationFailed, "Partition #{id} differs from frozen source (missing, changed, or extra items)"
      end
      expected.each { |item| fingerprint.update(JSON.generate(item.sort.to_h) + "\n") }
      summary = expected.find { |item| item["sk"] == "SUMMARY" }
      %w[open_count click_count click_pair_count].each { |name| totals[name] += summary.fetch(name) }
      totals["repeat_open_count"] += expected.select { |item| item["sk"].start_with?("OPEN#") }.sum { |item| item.fetch("open_count") - 1 }
      partitions += 1
      item_count += expected.size
    end
    actual_count = 0
    scan_items do |item|
      next if key_for(item) == CONTROL_KEY
      actual_count += 1
      raise ReconciliationFailed, "Foreign/live item in target" unless item["migration_run_id"] == @run_id
    end
    raise ReconciliationFailed, "Extra target partitions: expected #{item_count} items, found #{actual_count}" unless actual_count == item_count
    raise UnsafeTarget, "Migration checkpoint changed during reconciliation" unless owned_control! == control
    totals.merge("partitions" => partitions, "items" => item_count, "sha256" => fingerprint.hexdigest)
  end

  def release!
    control = owned_control!
    raise UnsafeTarget, "Import and reconcile before release" unless %w[reconciled released].include?(control["state"])
    report = reconcile!
    unless report == control.fetch("report")
      raise ReconciliationFailed, "Source/report changed since import; use a new snapshot and empty table"
    end
    replace_control!(control, control.merge("state" => "released")) unless control["state"] == "released"
    report
  end

  private
    def projected_items(id)
      projection = EmailEngagementMigrationProjection.new(id)
      %w[open click].each { |kind| @source.each_row(kind, id) { |row| projection.add(kind, row) } }
      projection.items.map { |item| item.merge("migration_run_id" => @run_id) }
    end

    def claim_target!
      response = retry_request { @client.describe_table(table_name: @table_name) }
      schema = response.table.key_schema.map { |key| [key.attribute_name, key.key_type] }.sort
      types = response.table.attribute_definitions.to_h { |attribute| [attribute.attribute_name, attribute.attribute_type] }
      unless schema == [["pk", "HASH"], ["sk", "RANGE"]] && types.values_at("pk", "sk") == ["S", "S"]
        raise UnsafeTarget, "Target must have string pk HASH and sk RANGE keys"
      end
      existing = get(CONTROL_KEY)
      return owned_control! if existing
      scan_items { |_item| raise UnsafeTarget, "Refusing nonempty target without this migration's ownership marker" }
      control = CONTROL_KEY.merge("run_id" => @run_id, "snapshot_id" => @snapshot_id,
                                  "format_version" => FORMAT_VERSION, "state" => "importing", "last_partition" => 0)
      insert_immutable!(control)
      owned_control!
    end

    def owned_control!
      control = get(CONTROL_KEY)
      unless control && control.values_at("run_id", "snapshot_id", "format_version") == [@run_id, @snapshot_id, FORMAT_VERSION]
        raise UnsafeTarget, "Target belongs to another migration/snapshot, or lacks an ownership marker"
      end
      unless %w[importing reconciled released].include?(control["state"])
        raise UnsafeTarget, "Unknown migration state"
      end
      control
    end

    def replace_control!(old, replacement)
      retry_request do
        @client.put_item(table_name: @table_name, item: replacement,
                         condition_expression: "#run = :run AND #snapshot = :snapshot AND #state = :state AND #cursor = :cursor",
                         expression_attribute_names: { "#run" => "run_id", "#snapshot" => "snapshot_id", "#state" => "state", "#cursor" => "last_partition" },
                         expression_attribute_values: { ":run" => @run_id, ":snapshot" => @snapshot_id, ":state" => old.fetch("state"), ":cursor" => old.fetch("last_partition") })
      end
      replacement
    rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
      return replacement if get(CONTROL_KEY) == replacement
      raise UnsafeTarget, "Checkpoint changed concurrently; stop other migration writers"
    end

    def insert_immutable!(item)
      retry_request do
        @client.put_item(table_name: @table_name, item:, condition_expression: "attribute_not_exists(pk)")
      end
    rescue Aws::DynamoDB::Errors::ConditionalCheckFailedException
      return if get(key_for(item)) == item
      raise UnsafeTarget, "Refusing to overwrite changed/live item #{item.fetch('pk')}/#{item.fetch('sk')}"
    end

    def get(key)
      retry_request { @client.get_item(table_name: @table_name, key:, consistent_read: true) }.item
    end

    def query_partition(id)
      items = []
      cursor = nil
      loop do
        response = retry_request do
          @client.query(table_name: @table_name, consistent_read: true,
                        key_condition_expression: "pk = :pk", expression_attribute_values: { ":pk" => id.to_s },
                        exclusive_start_key: cursor)
        end
        items.concat(response.items)
        cursor = response.last_evaluated_key
        break if !cursor || cursor.empty?
      end
      items
    end

    def scan_items(&block)
      cursor = nil
      loop do
        response = retry_request { @client.scan(table_name: @table_name, consistent_read: true, exclusive_start_key: cursor) }
        response.items.each(&block)
        cursor = response.last_evaluated_key
        break if !cursor || cursor.empty?
      end
    end

    def key_for(item)
      item.slice("pk", "sk")
    end

    def retry_request
      attempts = 0
      begin
        yield
      rescue Aws::Errors::ServiceError, Seahorse::Client::NetworkingError => error
        attempts += 1
        retryable = error.is_a?(Seahorse::Client::NetworkingError) ||
          RETRYABLE_ERRORS.include?(error.code || error.class.name.split("::").last)
        raise unless retryable && attempts < MAX_ATTEMPTS
        @sleeper.call((0.1 + rand * 0.1) * 2**(attempts - 1))
        retry
      end
    end
end
