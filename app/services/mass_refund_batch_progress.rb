# frozen_string_literal: true

class MassRefundBatchProgress
  def self.update(batch_id:, purchase:)
    new(batch_id:, purchase:).update
  end

  def initialize(batch_id:, purchase:)
    @batch_id = batch_id
    @purchase = purchase
  end

  def update
    batch = MassRefundBatch.find_by(id: batch_id)
    return unless batch

    enqueue_finalizer = false

    batch.with_lock do
      apply_purchase_result(batch)
      enqueue_finalizer = ready_to_finalize?(batch) && !batch.completed?
      batch.save!
    end

    FinalizeMassRefundBatchWorker.perform_async(batch.id) if enqueue_finalizer
  rescue StandardError => e
    Rails.logger.error("MassRefundBatchProgress failed for batch #{batch_id}: #{e.class}: #{e.message}")
  end

  private
    attr_reader :batch_id, :purchase

    def apply_purchase_result(batch)
      if purchase.errors.any?
        errors = (batch.errors_by_purchase_id || {}).dup
        errors[purchase.id.to_s] = purchase.errors.full_messages.to_sentence
        batch.errors_by_purchase_id = errors
        batch.failed_count += 1
      elsif purchase.reload.stripe_refunded?
        batch.refunded_count += 1
      else
        batch.blocked_count += 1
      end
    end

    def ready_to_finalize?(batch)
      batch.processed_count >= batch.total_count
    end
end
