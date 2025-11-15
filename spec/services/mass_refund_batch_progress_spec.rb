# frozen_string_literal: true

require "spec_helper"

describe MassRefundBatchProgress do
  describe ".update" do
    let(:admin_user) { create(:admin_user) }
    let(:product) { create(:product) }
    let(:batch) { create(:mass_refund_batch, product:, admin_user:, status: :processing, purchase_ids: [1, 2]) }
    let(:purchase) { instance_double(Purchase, id: 1, errors: errors) }
    let(:errors) { instance_double(ActiveModel::Errors, any?: false, full_messages: []) }

    before do
      allow(purchase).to receive(:reload).and_return(purchase)
    end

    before do
      allow(FinalizeMassRefundBatchWorker).to receive(:perform_async)
    end

    it "increments refunded_count when the purchase is refunded" do
      allow(purchase).to receive(:stripe_refunded?).and_return(true)

      described_class.update(batch_id: batch.id, purchase:)

      batch.reload
      expect(batch.refunded_count).to eq(1)
      expect(batch.blocked_count).to eq(0)
      expect(batch.failed_count).to eq(0)
    end

    it "increments blocked_count when the buyer is only blocked" do
      allow(purchase).to receive(:stripe_refunded?).and_return(false)

      described_class.update(batch_id: batch.id, purchase:)

      batch.reload
      expect(batch.blocked_count).to eq(1)
      expect(batch.refunded_count).to eq(0)
    end

    it "records errors and increments failed_count" do
      allow(errors).to receive(:any?).and_return(true)
      allow(errors).to receive(:full_messages).and_return(["Card declined"])

      described_class.update(batch_id: batch.id, purchase:)

      batch.reload
      expect(batch.failed_count).to eq(1)
      expect(batch.errors_by_purchase_id["1"]).to eq("Card declined")
    end

    it "enqueues finalizer when all purchases finish" do
      batch.update!(purchase_ids: [1])
      allow(purchase).to receive(:stripe_refunded?).and_return(true)

      expect(FinalizeMassRefundBatchWorker).to receive(:perform_async).with(batch.id)

      described_class.update(batch_id: batch.id, purchase:)
      batch.reload
    end

    it "keeps the batch processing until all purchases finish" do
      allow(purchase).to receive(:stripe_refunded?).and_return(true)

      described_class.update(batch_id: batch.id, purchase:)

      batch.reload
      expect(batch.status).to eq("processing")
      expect(batch.completed_at).to be_nil
    end

    it "does nothing if the batch cannot be found" do
      expect {
        described_class.update(batch_id: 0, purchase:)
      }.not_to change { batch.reload.attributes }
    end
  end
end

