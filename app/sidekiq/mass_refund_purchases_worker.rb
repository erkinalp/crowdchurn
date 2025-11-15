# frozen_string_literal: true

class MassRefundPurchasesWorker
  include Sidekiq::Job
  sidekiq_options retry: 5, queue: :default, lock: :until_executed

  def perform(batch_id)
    batch = MassRefundBatch.find(batch_id)
    return if batch.completed?

    batch.update!(status: :processing, started_at: Time.current)

    # Enqueue individual refund workers for each purchase
    batch.purchase_ids.each do |purchase_id|
      RefundPurchaseWorker.perform_async(purchase_id, batch.admin_user_id, Refund::FRAUD, batch.id)
    end
  rescue StandardError => e
    Rails.logger.error("MassRefundPurchasesWorker failed for batch #{batch_id}: #{e.class}: #{e.message}")
    batch&.update!(status: :failed, error_message: e.message, completed_at: Time.current)
    raise
  end
end
