# frozen_string_literal: true

require "spec_helper"

describe MassRefundPurchasesWorker do
  let(:admin_user) { create(:admin_user) }
  let(:product) { create(:product) }

  describe "#perform" do
    let(:batch) { create(:mass_refund_batch, product:, admin_user:, purchase_ids: [1, 2]) }


    it "marks the batch as processing" do
      expect do
        described_class.new.perform(batch.id)
      end.to change { batch.reload.status }.from("pending").to("processing")
    end

    it "enqueues RefundPurchaseWorker jobs for each purchase" do
      expect(RefundPurchaseWorker).to receive(:perform_async).with(1, admin_user.id, Refund::FRAUD, batch.id)
      expect(RefundPurchaseWorker).to receive(:perform_async).with(2, admin_user.id, Refund::FRAUD, batch.id)

      described_class.new.perform(batch.id)
    end
  end
end
