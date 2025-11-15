# frozen_string_literal: true

require "spec_helper"

describe FinalizeMassRefundBatchWorker do
  let(:worker) { described_class.new }
  let(:batch) { create(:mass_refund_batch, status: :processing, purchase_ids: [1, 2], refunded_count: 2) }

  describe "#perform" do
    it "marks the batch as completed when processed_count matches total" do
      allow(batch).to receive(:processed_count).and_return(batch.total_count)
      allow(batch).to receive(:with_lock).and_yield
      allow(MassRefundBatch).to receive(:find_by).and_return(batch)

      expect(batch).to receive(:update!).with(status: :completed, completed_at: anything)
      worker.perform(batch.id)
    end

    it "does nothing if not all purchases processed" do
      allow(batch).to receive(:processed_count).and_return(batch.total_count - 1)
      allow(batch).to receive(:with_lock).and_yield
      allow(MassRefundBatch).to receive(:find_by).and_return(batch)

      expect(batch).not_to receive(:update!)
      worker.perform(batch.id)
    end

    it "returns when batch is already completed" do
      batch.update!(status: :completed, completed_at: Time.current)
      expect(MassRefundBatch).to receive(:find_by).and_return(batch)
      expect(batch).not_to receive(:with_lock)
      worker.perform(batch.id)
    end
  end
end

