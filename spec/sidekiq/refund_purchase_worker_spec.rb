# frozen_string_literal: true

require "spec_helper"

describe RefundPurchaseWorker do
  describe "#perform" do
    let(:admin_user) { create(:admin_user) }
    let(:purchase_id) { 1 }
    let(:purchase_double) { double(id: purchase_id) }

    before do
      expect(Purchase).to receive(:find).with(purchase_id).and_return(purchase_double)
    end

    context "when the reason is `Refund::FRAUD`" do
      it "calls #refund_for_fraud_and_block_buyer! on the purchase" do
        expect(purchase_double).to receive(:refund_for_fraud_and_block_buyer!).with(admin_user.id)

        described_class.new.perform(purchase_id, admin_user.id, Refund::FRAUD)
      end
    end

    context "when the reason is not supplied" do
      it "calls #refund_and_save! on the purchase" do
        expect(purchase_double).to receive(:refund_and_save!).with(admin_user.id)

        described_class.new.perform(purchase_id, admin_user.id)
      end
    end

    context "when batch_id is provided" do
      let(:batch_id) { 123 }
      before do
        allow(purchase_double).to receive(:refund_for_fraud_and_block_buyer!).with(admin_user.id)
      end

      it "delegates batch progress updates to MassRefundBatchProgress" do
        expect(MassRefundBatchProgress).to receive(:update).with(batch_id:, purchase: purchase_double)

        described_class.new.perform(purchase_id, admin_user.id, Refund::FRAUD, batch_id)
      end
    end
  end
end
