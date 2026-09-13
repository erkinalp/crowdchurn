# frozen_string_literal: true

class EmailEngagementMigrationSource
  COLLECTIONS = { "open" => "creator_email_open_events", "click" => "creator_email_click_events" }.freeze
  MAX_ATTEMPTS = 5

  def self.connect(uri:, database:, page_size: 500)
    # Mongo is deliberately absent from the application boot path.
    require "mongo"
    client = Mongo::Client.new(uri, database:, server_selection_timeout: 10)
    new(client, page_size:)
  end

  def initialize(database, page_size: 500, sleeper: Kernel.method(:sleep))
    raise ArgumentError, "page_size must be positive" unless page_size.positive?
    @database = database
    @page_size = page_size
    @sleeper = sleeper
  end

  def validate!
    missing = COLLECTIONS.values - retry_read { @database.database.collection_names }
    raise "Missing source collections: #{missing.join(', ')}" unless missing.empty?
    COLLECTIONS.each_value do |name|
      # Mongo range comparisons are type-bracketed; mixed _id types could silently skip rows.
      conditions = [
        { "_id" => { "$not" => { "$type" => "objectId" } } },
        { "installment_id" => { "$not" => { "$type" => "number" } } },
        { "installment_id" => { "$lte" => 0 } },
      ]
      invalid = retry_read { @database[name].find("$or" => conditions).limit(1).to_a }
      raise "Invalid installment_id or non-ObjectId _id in #{name}" unless invalid.empty?
    end
  end

  def each_partition(after: 0)
    cursor = after
    loop do
      next_ids = COLLECTIONS.values.filter_map do |name|
        row = retry_read do
          @database[name].find("installment_id" => { "$gt" => cursor })
            .sort("installment_id" => 1).projection("installment_id" => 1).limit(1).to_a.first
        end
        row&.fetch("installment_id")
      end
      break if next_ids.empty?
      cursor = next_ids.min
      raise "installment_id must be a positive integer" unless cursor.is_a?(Integer) && cursor.positive?
      yield cursor
    end
  end

  def each_row(kind, installment_id, &block)
    cursor = nil
    loop do
      filter = { "installment_id" => installment_id }
      filter["_id"] = { "$gt" => cursor } if cursor
      # Materialize a page before yielding: retrying a failed cursor never yields half a page twice.
      rows = retry_read do
        @database[COLLECTIONS.fetch(kind)].find(filter).sort("_id" => 1).limit(@page_size).to_a
      end
      break if rows.empty?
      rows.each(&block)
      cursor = rows.last.fetch("_id")
    end
  end

  def close
    @database.close
  end

  private
    def retry_read
      attempts = 0
      begin
        yield
      rescue StandardError => error
        attempts += 1
        retryable = error.class.name.match?(/\AMongo::Error::(Socket|NoServerAvailable|OperationFailure|CursorNotFound)/)
        raise unless retryable && attempts < MAX_ATTEMPTS
        @sleeper.call(0.2 * 2**(attempts - 1))
        retry
      end
    end
end
