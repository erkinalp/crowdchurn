# frozen_string_literal: true

class FinalizeMassRefundBatchWorker
  include Sidekiq::Job
  sidekiq_options retry: 3, queue: :default

  def perform(batch_id)
    batch = MassRefundBatch.find_by(id: batch_id)
    return unless batch
    return if batch.completed?

    batch.with_lock do
      next unless batch.processed_count >= batch.total_count
      batch.update!(status: :completed, completed_at: Time.current)
    end
  end
end
