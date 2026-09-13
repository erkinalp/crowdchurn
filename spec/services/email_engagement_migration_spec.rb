# frozen_string_literal: true

require "rspec"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/enumerable"
require_relative "../../app/services/email_engagement_migration"
require_relative "../../app/services/email_engagement_migration_source"

RSpec.describe EmailEngagementMigration do
  class Snapshot
    attr_reader :rows, :visited

    def initialize(rows)
      @rows = rows
      @visited = []
    end

    def validate!; end

    def each_partition(after: 0)
      raise "Mongo keyset cursors must be integers, not Dynamo BigDecimals" unless after.is_a?(Integer)
      rows.values.flatten.map { |row| row.fetch("installment_id") }.uniq.sort.each do |id|
        next unless id > after
        @visited << id
        yield id
      end
    end

    def each_row(kind, id, &block)
      rows.fetch(kind).select { |row| row["installment_id"] == id }.each(&block)
    end
  end

  class DynamoHarness
    attr_reader :client, :items
    attr_accessor :before_put, :after_put

    def initialize
      @items = {}
      @client = Aws::DynamoDB::Client.new(stub_responses: true, region: "us-east-1")
      table = {
        key_schema: [{ attribute_name: "pk", key_type: "HASH" }, { attribute_name: "sk", key_type: "RANGE" }],
        attribute_definitions: [{ attribute_name: "pk", attribute_type: "S" }, { attribute_name: "sk", attribute_type: "S" }],
      }
      client.stub_responses(:describe_table, table:)
      client.stub_responses(:get_item, lambda do |context|
        { item: items[decode(context.params.fetch(:key)).values_at("pk", "sk")] }
      end)
      client.stub_responses(:put_item, lambda do |context|
        params = context.params
        item = decode(params.fetch(:item))
        before_put&.call(item)
        key = item.values_at("pk", "sk")
        existing = items[key]
        allowed = if params[:condition_expression] == "attribute_not_exists(pk)"
          !existing
        else
          values = decode(params.fetch(:expression_attribute_values))
          existing && existing.values_at("run_id", "snapshot_id", "state", "last_partition") == values.values_at(":run", ":snapshot", ":state", ":cursor")
        end
        raise Aws::DynamoDB::Errors::ConditionalCheckFailedException.new(nil, "occupied") unless allowed
        items[key] = Marshal.load(Marshal.dump(item))
        after_put&.call(item)
        {}
      end)
      client.stub_responses(:query, lambda do |context|
        params = context.params
        pk = decode(params.fetch(:expression_attribute_values)).fetch(":pk")
        page(items.values.select { |item| item["pk"] == pk }, params)
      end)
      client.stub_responses(:scan, lambda do |context|
        page(items.values, context.params)
      end)
    end

    def decode(hash)
      hash.transform_values do |attribute|
        type, value = attribute.first
        case type
        when :n then BigDecimal(value).to_i
        when :m then decode(value)
        else value
        end
      end
    end

    def page(records, params)
      raise "Migration reads must be strongly consistent" unless params[:consistent_read]
      sorted = records.sort_by { |item| item.values_at("pk", "sk") }
      if params[:exclusive_start_key]
        key = decode(params[:exclusive_start_key]).values_at("pk", "sk")
        sorted = sorted.drop_while { |item| (item.values_at("pk", "sk") <=> key) <= 0 }
      end
      selected = sorted.take(2)
      { items: selected, last_evaluated_key: sorted.size > 2 ? selected.last.slice("pk", "sk") : nil }
    end
  end

  let(:method) { "CreatorContactingCustomersMailer.purchase_installment" }
  let(:args) { "[123, 456]" }
  let(:first_time) { Time.iso8601("2020-01-01T01:02:03.123Z") }
  let(:last_time) { Time.iso8601("2020-02-02T03:04:05.456Z") }
  let(:url) { "https://www&#46;example&#46;com/a?x=1%2E2" }
  let(:harness) { DynamoHarness.new }
  let(:source) { Snapshot.new("open" => [], "click" => []) }
  let(:sleeper) { double("sleeper", call: nil) }

  def row(kind, id: "one", installment_id: 10, mailer_args: args, times: [first_time], count: 1, click_url: url)
    { "_id" => id, "installment_id" => installment_id, "mailer_method" => method, "mailer_args" => mailer_args,
      "#{kind}_timestamps" => times, "#{kind}_count" => count }.tap do |attributes|
      attributes["click_url"] = click_url if kind == "click"
    end
  end

  def migration(**overrides)
    settings = {
      source:, client: harness.client, table_name: "frozen-email_engagement", active_table_name: "production-email_engagement",
      run_id: "run-one", snapshot_id: "snapshot-one", source_frozen: true, target_isolated: true, sleeper:,
    }
    described_class.new(**settings.merge(overrides))
  end

  def stored(sk, pk: "10")
    harness.items.fetch([pk, sk])
  end

  def control
    harness.items.fetch(described_class::CONTROL_KEY.values_at("pk", "sk"))
  end

  def recipient(mailer_args = args)
    Digest::SHA256.hexdigest("#{method}\n#{mailer_args}")
  end

  it "preserves exact digests, serialized arguments, encoded URLs, timestamps and repeated opens while rebuilding all counters" do
    source.rows["open"] << row("open", times: [last_time, first_time], count: 5)
    source.rows["click"] << row("click", id: "a", times: [first_time])
    source.rows["click"] << row("click", id: "b", click_url: "view_attachments_url", times: [last_time])
    source.rows["click"] << row("click", id: "c", mailer_args: "[123,456]", times: [last_time])

    report = migration.import!

    expect(stored("OPEN##{recipient}")).to include(
      "mailer_args" => "[123, 456]", "open_count" => 5,
      "first_open_at" => "2020-01-01T01:02:03.123Z", "last_open_at" => "2020-02-02T03:04:05.456Z"
    )
    expect(stored("CLICK##{recipient}##{Digest::SHA256.hexdigest(url)}")).to include("click_url" => url, "first_click_at" => "2020-01-01T01:02:03.123Z")
    expect(stored("CLICKER##{recipient}")).to include("first_click_at" => "2020-01-01T01:02:03.123Z", "last_click_at" => "2020-02-02T03:04:05.456Z")
    expect(stored("URL##{Digest::SHA256.hexdigest(url)}")["click_count"]).to eq(2)
    expect(stored("URL##{Digest::SHA256.hexdigest('view_attachments_url')}")["click_count"]).to eq(1)
    expect(stored("SUMMARY")).to include("open_count" => 2, "click_count" => 2, "click_pair_count" => 3)
    expect(report).to include("repeat_open_count" => 4, "partitions" => 1, "items" => 10)
    expect(migration.reconcile!).to eq(report)
    expect(harness.client.api_requests.map { |request| request[:operation_name] }).not_to include(:transact_write_items, :update_item)
  end

  it "deduplicates repeated source IDs and identical duplicate histories without losing same-timestamp repeat opens" do
    original = row("open", times: [first_time], count: 4)
    source.rows["open"].concat([original, original.dup, original.merge("_id" => "duplicate")])
    source.rows["click"].concat([row("click"), row("click", id: "duplicate", times: [last_time])])
    migration.import!
    expect(stored("OPEN##{recipient}")["open_count"]).to eq(4)
    expect(stored("SUMMARY")).to include("open_count" => 1, "click_count" => 1, "click_pair_count" => 1)
    expect(stored("CLICK##{recipient}##{Digest::SHA256.hexdigest(url)}")).to include("first_click_at" => first_time.iso8601(3), "last_click_at" => last_time.iso8601(3))
  end

  it "unions overlapping observed timestamps and adds counts for disjoint repeat-open histories" do
    source.rows["open"].concat(
      [
        row("open", id: "a", times: [first_time], count: 1),
        row("open", id: "b", times: [first_time, last_time], count: 2),
        row("open", id: "c", times: [Time.iso8601("2021-01-01T00:00:00.000Z")], count: 3),
      ]
    )
    migration.import!
    expect(stored("OPEN##{recipient}")["open_count"]).to eq(5)
  end

  it "fails on ambiguous duplicate repeat counts instead of silently summing or discarding history" do
    source.rows["open"].concat([row("open", count: 3), row("open", id: "other", times: [first_time, last_time], count: 4)])
    expect { migration.import! }.to raise_error(EmailEngagementMigrationProjection::InvalidSource, /Ambiguous/)
    expect(control["last_partition"]).to eq(0)
  end

  it "fails when the same source ID changes during a page replay" do
    source.rows["open"].concat([row("open"), row("open", count: 2)])
    expect { migration.import! }.to raise_error(EmailEngagementMigrationProjection::InvalidSource, /Source changed/)
  end

  it "synthesizes exactly one open at the earliest click when several URLs have no open row" do
    source.rows["click"].concat([row("click", times: [last_time]), row("click", id: "other", click_url: "https://example&#46;org", times: [first_time])])
    migration.import!
    expect(stored("OPEN##{recipient}")).to include("open_count" => 1, "first_open_at" => first_time.iso8601(3), "last_open_at" => first_time.iso8601(3))
  end

  it "does not invent opens or alter the first/last timestamps of existing Mongo open rows when clicks came earlier" do
    source.rows["open"] << row("open", times: [last_time], count: 2)
    source.rows["click"] << row("click", times: [first_time])
    migration.import!
    expect(stored("OPEN##{recipient}")).to include("open_count" => 2, "first_open_at" => last_time.iso8601(3), "last_open_at" => last_time.iso8601(3))
  end

  it "resumes an interrupted partition and independently rechecks completed partitions without inflating counts" do
    source.rows["open"].concat([row("open"), row("open", id: "two", installment_id: 20, count: 7)])
    harness.after_put = lambda do |item|
      raise "process stopped after acknowledged data write" if item["pk"] == "20"
    end
    expect { migration.import! }.to raise_error(/process stopped/)
    expect(control["last_partition"]).to eq(10)
    harness.after_put = nil
    report = migration.import!
    expect(stored("OPEN##{recipient}", pk: "20")["open_count"]).to eq(7)
    expect(report).to include("partitions" => 2, "open_count" => 2, "repeat_open_count" => 6)
    expect(source.visited.count(10)).to be >= 2
    expect(migration.import!).to eq(report)
  end

  it "handles committed writes with lost responses, including checkpoints, using conditional equality checks" do
    source.rows["open"] << row("open", count: 8)
    failed = Set.new
    harness.after_put = lambda do |item|
      token = [item["pk"], item["sk"], item["state"], item["last_partition"]]
      unless failed.include?(token)
        failed << token
        raise Aws::DynamoDB::Errors::InternalServerError.new(nil, "lost acknowledgement")
      end
    end
    migration.import!
    expect(stored("OPEN##{recipient}")["open_count"]).to eq(8)
    expect(control["state"]).to eq("reconciled")
    expect(sleeper).to have_received(:call).at_least(:once)
  end

  it "bounds throttling retries and can resume after exhaustion" do
    harness.before_put = ->(_item) { raise Aws::DynamoDB::Errors::ProvisionedThroughputExceededException.new(nil, "throttle") }
    expect { migration.import! }.to raise_error(Aws::DynamoDB::Errors::ProvisionedThroughputExceededException)
    expect(sleeper).to have_received(:call).exactly(described_class::MAX_ATTEMPTS - 1).times
    harness.before_put = nil
    expect(migration.import!["items"]).to eq(0)
  end

  it "refuses unsafe active tables and missing source/target isolation attestations before contacting Dynamo" do
    expect { migration(table_name: "production-email_engagement") }.to raise_error(described_class::UnsafeTarget)
    expect { migration(source_frozen: false) }.to raise_error(described_class::UnsafeTarget)
    expect { migration(target_isolated: false) }.to raise_error(described_class::UnsafeTarget)
    expect(harness.client.api_requests).to be_empty
  end

  it "refuses existing live data and a different snapshot or run owner" do
    harness.items[["99", "SUMMARY"]] = { "pk" => "99", "sk" => "SUMMARY", "open_count" => 9 }
    expect { migration.import! }.to raise_error(described_class::UnsafeTarget, /nonempty/)
    harness.items.clear
    migration.import!
    expect { migration(snapshot_id: "different").import! }.to raise_error(described_class::UnsafeTarget, /another migration/)
    expect { migration(run_id: "different").import! }.to raise_error(described_class::UnsafeTarget, /another migration/)
  end

  it "never overwrites a changed existing item on resumption" do
    source.rows["open"] << row("open")
    harness.after_put = ->(item) { raise "interrupted" if item["sk"].start_with?("OPEN#") }
    expect { migration.import! }.to raise_error(/interrupted/)
    harness.after_put = nil
    stored("OPEN##{recipient}")["open_count"] = 999
    expect { migration.import! }.to raise_error(described_class::UnsafeTarget, /overwrite/)
    expect(stored("OPEN##{recipient}")["open_count"]).to eq(999)
  end

  it "detects missing derived items, corrupt counters and extra target partitions during independent reconciliation" do
    source.rows["click"] << row("click")
    migration.import!
    original = Marshal.load(Marshal.dump(harness.items))
    harness.items.delete(["10", "URL##{Digest::SHA256.hexdigest(url)}"])
    expect { migration.reconcile! }.to raise_error(described_class::ReconciliationFailed, /Partition 10/)
    harness.items.replace(Marshal.load(Marshal.dump(original)))
    stored("SUMMARY")["click_count"] = 200
    expect { migration.reconcile! }.to raise_error(described_class::ReconciliationFailed, /Partition 10/)
    harness.items.replace(Marshal.load(Marshal.dump(original)))
    harness.items[["999", "SUMMARY"]] = { "pk" => "999", "sk" => "SUMMARY", "migration_run_id" => "run-one" }
    expect { migration.reconcile! }.to raise_error(described_class::ReconciliationFailed, /Extra target partitions/)
  end

  it "does not trust an advanced checkpoint that skipped unwritten history" do
    source.rows["open"] << row("open")
    harness.after_put = ->(item) { raise "interrupted" if item["sk"] == "CONTROL" }
    expect { migration.import! }.to raise_error(/interrupted/)
    harness.after_put = nil
    control["last_partition"] = 999
    expect { migration.import! }.to raise_error(described_class::ReconciliationFailed, /Partition 10/)
  end

  it "detects changes to a completed source partition even when resuming beyond its checkpoint" do
    source.rows["open"] << row("open")
    migration.import!
    source.rows["open"].first["open_count"] = 8
    expect { migration.import! }.to raise_error(described_class::ReconciliationFailed)
    expect { migration.release! }.to raise_error(described_class::ReconciliationFailed)
  end

  it "refuses a target with incompatible key types before writing any marker" do
    table = {
      key_schema: [{ attribute_name: "id", key_type: "HASH" }],
      attribute_definitions: [{ attribute_name: "id", attribute_type: "N" }],
    }
    harness.client.stub_responses(:describe_table, table:)
    expect { migration.import! }.to raise_error(described_class::UnsafeTarget, /string pk/)
    expect(harness.items).to be_empty
  end

  it "refuses to release an interrupted import" do
    harness.after_put = ->(_item) { raise "interrupted" }
    expect { migration.import! }.to raise_error(/interrupted/)
    harness.after_put = nil
    expect { migration.release! }.to raise_error(described_class::UnsafeTarget, /Import and reconcile/)
  end

  it "requires a fresh full reconciliation before release and refuses future imports into the released table" do
    source.rows["open"] << row("open")
    report = migration.import!
    expect(migration.release!).to eq(report)
    expect(control["state"]).to eq("released")
    expect(migration.release!).to eq(report)
    expect { migration.import! }.to raise_error(described_class::UnsafeTarget, /Released/)
  end

  it "rejects malformed historical values rather than inventing timestamps or serializing arguments" do
    [row("open", times: []), row("open", count: 0), row("open", mailer_args: [123, 456]),
     row("open", times: [Time.iso8601("2020-01-01T00:00:00.123456Z")])].each do |invalid|
      projection = EmailEngagementMigrationProjection.new(10)
      expect { projection.add("open", invalid) }.to raise_error(EmailEngagementMigrationProjection::InvalidSource)
    end
  end

  it "normalizes timezone offsets without changing millisecond instants" do
    source.rows["open"] << row("open", times: ["2020-01-01T06:32:03.123+05:30"])
    migration.import!
    expect(stored("OPEN##{recipient}")["first_open_at"]).to eq("2020-01-01T01:02:03.123Z")
  end

  it "selects the engagement-only table override without changing other stores' prefix" do
    previous = ENV["EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME"]
    ENV["EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME"] = "released-email_engagement"
    expect(EmailEngagementDynamoStore.table_name).to eq("released-email_engagement")
  ensure
    previous ? ENV["EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME"] = previous : ENV.delete("EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME")
  end
end

RSpec.describe EmailEngagementMigrationSource do
  def view(rows)
    double("Mongo view").tap do |result|
      allow(result).to receive(:sort).and_return(result)
      allow(result).to receive(:projection).and_return(result)
      allow(result).to receive(:limit).and_return(result)
      allow(result).to receive(:to_a).and_return(rows)
    end
  end

  it "paginates source rows by _id and retries a failed page before yielding any of its documents" do
    stub_const("Mongo::Error::SocketError", Class.new(StandardError))
    collection = double("collection")
    database = double("database", :[] => collection)
    first = view([{ "_id" => 1 }, { "_id" => 2 }])
    calls = 0
    allow(first).to receive(:to_a) do
      calls += 1
      raise Mongo::Error::SocketError, "disconnect" if calls == 1
      [{ "_id" => 1 }, { "_id" => 2 }]
    end
    expect(collection).to receive(:find).with({ "installment_id" => 10 }).twice.and_return(first)
    expect(collection).to receive(:find).with({ "installment_id" => 10, "_id" => { "$gt" => 2 } }).and_return(view([{ "_id" => 3 }]))
    expect(collection).to receive(:find).with({ "installment_id" => 10, "_id" => { "$gt" => 3 } }).and_return(view([]))
    source = described_class.new(database, page_size: 2, sleeper: ->(_seconds) { })
    rows = []
    source.each_row("open", 10) { |row| rows << row }
    expect(rows.map { |row| row["_id"] }).to eq([1, 2, 3])
  end

  it "merges the two collection installment streams including click-only posts and starts after a checkpoint" do
    opens = double("opens")
    clicks = double("clicks")
    database = double("database")
    allow(database).to receive(:[]).with("creator_email_open_events").and_return(opens)
    allow(database).to receive(:[]).with("creator_email_click_events").and_return(clicks)
    [[0, 10, 20], [10, 30, 20], [20, 30, nil], [30, nil, nil]].each do |cursor, open_id, click_id|
      allow(opens).to receive(:find).with("installment_id" => { "$gt" => cursor }).and_return(view(open_id ? [{ "installment_id" => open_id }] : []))
      allow(clicks).to receive(:find).with("installment_id" => { "$gt" => cursor }).and_return(view(click_id ? [{ "installment_id" => click_id }] : []))
    end
    source = described_class.new(database)
    ids = []
    source.each_partition { |id| ids << id }
    expect(ids).to eq([10, 20, 30])
    resumed = []
    source.each_partition(after: 10) { |id| resumed << id }
    expect(resumed).to eq([20, 30])
  end

  it "refuses a misspelled or incomplete source database rather than importing an apparently empty snapshot" do
    database = double("client", database: double("database", collection_names: ["creator_email_open_events"]))
    expect { described_class.new(database).validate! }.to raise_error(/Missing source collections: creator_email_click_events/)
  end

  it "checks malformed installment IDs and mixed _id types instead of silently filtering them out of the keyset scan" do
    collection = double("collection")
    expect(collection).to receive(:find).with("$or" => array_including(
      { "_id" => { "$not" => { "$type" => "objectId" } } },
      { "installment_id" => { "$not" => { "$type" => "number" } } }
    )).and_return(view([{ "_id" => 1 }]))
    database = double("client", database: double("database", collection_names: described_class::COLLECTIONS.values), :[] => collection)
    expect { described_class.new(database).validate! }.to raise_error(/Invalid installment_id/)
  end
end

RSpec.describe "Email engagement cutover gate" do
  let(:client) { Aws::DynamoDB::Client.new(stub_responses: true, region: "us-east-1") }

  around do |example|
    names = %w[EMAIL_ENGAGEMENT_MIGRATION_RUN_ID EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME]
    previous = names.index_with { |name| ENV[name] }
    ENV["EMAIL_ENGAGEMENT_MIGRATION_RUN_ID"] = "released-run"
    ENV["EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME"] = "released-email_engagement"
    example.run
  ensure
    previous.each { |name, value| value ? ENV[name] = value : ENV.delete(name) }
  end

  before do
    configuration = double("configuration")
    allow(configuration).to receive(:after_initialize).and_yield
    stub_const("Rails", double("Rails", application: double("application", config: configuration)))
    allow(EmailEngagementDynamoStore).to receive(:client).and_return(client)
  end

  def run_initializer
    load File.expand_path("../../config/initializers/email_engagement_migration.rb", __dir__)
  end

  it "allows boot only after the selected target was released for the requested run" do
    client.stub_responses(:get_item, item: { "state" => "released", "run_id" => "released-run" })
    expect { run_initializer }.not_to raise_error
    expect(client.api_requests.first[:params]).to include(table_name: "released-email_engagement", consistent_read: true)
  end

  it "fails closed on missing, importing or differently owned targets" do
    [nil, { "state" => "importing", "run_id" => "released-run" }, { "state" => "released", "run_id" => "different-run" }].each do |item|
      client.stub_responses(:get_item, item:)
      expect { run_initializer }.to raise_error(/has not been reconciled\/released/)
    end
  end

  it "does not make boot-time requests for deployments without a migration release gate" do
    ENV.delete("EMAIL_ENGAGEMENT_MIGRATION_RUN_ID")
    run_initializer
    expect(client.api_requests).to be_empty
  end
end
