# frozen_string_literal: true

describe HandleKillbillEventWorker do
  describe "perform" do
    it "calls the KillbillChargeProcessor.handle_killbill_event" do
      killbill_event = {
        "eventType" => "PAYMENT_SUCCESS",
        "eventId" => "evt_123",
        "objectId" => "payment_456",
        "eventDate" => "2024-01-01T12:00:00Z"
      }

      expect(KillbillChargeProcessor).to receive(:handle_killbill_event).with(killbill_event)
      described_class.new.perform(killbill_event)
    end

    it "handles PAYMENT_FAILED events" do
      killbill_event = {
        "eventType" => "PAYMENT_FAILED",
        "eventId" => "evt_456",
        "objectId" => "payment_789",
        "eventDate" => "2024-01-01T12:00:00Z"
      }

      expect(KillbillChargeProcessor).to receive(:handle_killbill_event).with(killbill_event)
      described_class.new.perform(killbill_event)
    end

    it "handles PAYMENT_REFUND events" do
      killbill_event = {
        "eventType" => "PAYMENT_REFUND",
        "eventId" => "evt_789",
        "objectId" => "payment_abc",
        "transactionId" => "txn_def",
        "eventDate" => "2024-01-01T12:00:00Z"
      }

      expect(KillbillChargeProcessor).to receive(:handle_killbill_event).with(killbill_event)
      described_class.new.perform(killbill_event)
    end

    it "handles PAYMENT_CHARGEBACK events" do
      killbill_event = {
        "eventType" => "PAYMENT_CHARGEBACK",
        "eventId" => "evt_chargeback",
        "objectId" => "payment_xyz",
        "eventDate" => "2024-01-01T12:00:00Z"
      }

      expect(KillbillChargeProcessor).to receive(:handle_killbill_event).with(killbill_event)
      described_class.new.perform(killbill_event)
    end
  end
end
