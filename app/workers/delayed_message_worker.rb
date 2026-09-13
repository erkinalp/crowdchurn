# frozen_string_literal: true

class DelayedMessageWorker
  include Sidekiq::Worker

  sidekiq_options queue: :default, retry: 3

  def perform
    # Process delayed messages for purchases from the last 60 days
    # (older purchases unlikely to have delayed messages pending)
    Purchase.successful
            .where("created_at > ?", 60.days.ago)
            .where("created_at < ?", 1.hour.ago) # Give some buffer
            .find_in_batches(batch_size: 100) do |purchases|
      purchases.each do |purchase|
        process_delayed_messages_for_purchase(purchase)
      end
    end
  end

  private
    def process_delayed_messages_for_purchase(purchase)
      MessageTriggerService.new(purchase).process_delayed_triggers
    rescue => e
      Rails.logger.error("Failed to process delayed messages for purchase #{purchase.id}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry)
    end
end
