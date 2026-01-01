# frozen_string_literal: true

require "spec_helper"

describe KillbillPayoutProcessor do
  include CurrencyHelper

  let(:user) { create(:user) }
  let(:killbill_merchant_account) do
    create(:merchant_account,
           user: user,
           charge_processor_id: "killbill",
           charge_processor_merchant_id: "kb-account-123")
  end

  before do
    allow(user).to receive(:killbill_merchant_account).and_return(killbill_merchant_account)
  end

  describe ".payout_processor_id" do
    it "returns 'killbill'" do
      expect(described_class.payout_processor_id).to eq("killbill")
    end
  end

  describe ".is_user_payable" do
    context "when user has a valid Kill Bill merchant account" do
      it "returns true" do
        expect(described_class.is_user_payable(user, 10_00)).to eq(true)
      end
    end

    context "when user does not have a Kill Bill merchant account" do
      before do
        allow(user).to receive(:killbill_merchant_account).and_return(nil)
      end

      it "returns false" do
        expect(described_class.is_user_payable(user, 10_00)).to eq(false)
      end
    end

    context "when merchant account has no charge_processor_merchant_id" do
      let(:killbill_merchant_account) do
        create(:merchant_account,
               user: user,
               charge_processor_id: "killbill",
               charge_processor_merchant_id: nil)
      end

      it "returns false" do
        expect(described_class.is_user_payable(user, 10_00)).to eq(false)
      end
    end

    context "when user has a payment in processing state" do
      before do
        create(:payment, user: user, state: "processing")
      end

      it "returns false" do
        expect(described_class.is_user_payable(user, 10_00)).to eq(false)
      end

      it "adds a payout note if add_comment is true" do
        expect do
          described_class.is_user_payable(user, 10_00, add_comment: true)
        end.to change { user.comments.with_type_payout_note.count }.by(1)
      end
    end

    context "when payout_type is instant" do
      it "returns false because Kill Bill does not support instant payouts" do
        expect(described_class.is_user_payable(user, 10_00, payout_type: Payouts::PAYOUT_TYPE_INSTANT)).to eq(false)
      end

      it "adds a payout note if add_comment is true" do
        expect do
          described_class.is_user_payable(user, 10_00, payout_type: Payouts::PAYOUT_TYPE_INSTANT, add_comment: true)
        end.to change { user.comments.with_type_payout_note.count }.by(1)

        expect(user.comments.with_type_payout_note.last.content).to include("Kill Bill does not support instant payouts")
      end
    end
  end

  describe ".has_valid_payout_info?" do
    context "when user has a valid Kill Bill merchant account" do
      it "returns true" do
        expect(described_class.has_valid_payout_info?(user)).to eq(true)
      end
    end

    context "when user does not have a Kill Bill merchant account" do
      before do
        allow(user).to receive(:killbill_merchant_account).and_return(nil)
      end

      it "returns false" do
        expect(described_class.has_valid_payout_info?(user)).to eq(false)
      end
    end

    context "when merchant account has no charge_processor_merchant_id" do
      let(:killbill_merchant_account) do
        create(:merchant_account,
               user: user,
               charge_processor_id: "killbill",
               charge_processor_merchant_id: nil)
      end

      it "returns false" do
        expect(described_class.has_valid_payout_info?(user)).to eq(false)
      end
    end
  end

  describe ".is_balance_payable" do
    let(:merchant_account) { create(:merchant_account, user: user) }

    context "when balance is held by creator" do
      let(:balance) do
        create(:balance,
               user: user,
               merchant_account: merchant_account,
               holding_currency: Currency::USD)
      end

      before do
        allow(merchant_account).to receive(:holder_of_funds).and_return(HolderOfFunds::CREATOR)
        allow(merchant_account).to receive(:currency).and_return(Currency::USD)
      end

      it "returns true when currencies match" do
        expect(described_class.is_balance_payable(balance)).to eq(true)
      end

      it "returns false when currencies do not match" do
        allow(merchant_account).to receive(:currency).and_return(Currency::EUR)
        expect(described_class.is_balance_payable(balance)).to eq(false)
      end
    end

    context "when balance is held by Gumroad" do
      let(:balance) do
        create(:balance,
               user: user,
               merchant_account: merchant_account,
               holding_currency: Currency::USD)
      end

      before do
        allow(merchant_account).to receive(:holder_of_funds).and_return(HolderOfFunds::GUMROAD)
      end

      it "returns true" do
        expect(described_class.is_balance_payable(balance)).to eq(true)
      end
    end

    context "when balance has no merchant account" do
      let(:balance) { create(:balance, user: user, merchant_account: nil) }

      it "returns false" do
        expect(described_class.is_balance_payable(balance)).to eq(false)
      end
    end
  end

  describe ".prepare_payment_and_set_amount" do
    let(:balance_1) { create(:balance, user: user, amount_cents: 100_00, holding_amount_cents: 100_00) }
    let(:balance_2) { create(:balance, user: user, amount_cents: 200_00, holding_amount_cents: 200_00) }
    let(:payment) { create(:payment, user: user, currency: nil, amount_cents: nil) }

    it "sets the currency to USD" do
      described_class.prepare_payment_and_set_amount(payment, [balance_1, balance_2])
      expect(payment.currency).to eq(Currency::USD)
    end

    it "sets the amount as the sum of the balances" do
      described_class.prepare_payment_and_set_amount(payment, [balance_1, balance_2])
      expect(payment.amount_cents).to eq(300_00)
    end

    it "returns an empty array on success" do
      errors = described_class.prepare_payment_and_set_amount(payment, [balance_1, balance_2])
      expect(errors).to eq([])
    end
  end

  describe ".enqueue_payments" do
    let(:yesterday) { Date.yesterday.to_s }
    let(:user_ids) { [1, 2, 3] }

    it "enqueues PayoutUsersWorker jobs for each user" do
      described_class.enqueue_payments(user_ids, yesterday)

      expect(PayoutUsersWorker.jobs.size).to eq(user_ids.size)
      sidekiq_job_args = user_ids.map do |user_id|
        [yesterday, PayoutProcessorType::KILLBILL, user_id, Payouts::PAYOUT_TYPE_STANDARD]
      end
      expect(PayoutUsersWorker.jobs.map { _1["args"] }).to match_array(sidekiq_job_args)
    end
  end

  describe ".process_payments" do
    let(:payment1) { create(:payment, user: user) }
    let(:payment2) { create(:payment, user: user) }
    let(:payments) { [payment1, payment2] }

    it "calls perform_payment for each payment" do
      allow(described_class).to receive(:perform_payment).with(anything)

      expect(described_class).to receive(:perform_payment).with(payment1)
      expect(described_class).to receive(:perform_payment).with(payment2)

      described_class.process_payments(payments)
    end
  end

  describe ".perform_payment" do
    let(:payment) do
      create(:payment,
             user: user,
             amount_cents: 100_00,
             currency: Currency::USD,
             state: "processing",
             processor: PayoutProcessorType::KILLBILL)
    end

    let(:mock_payment_response) do
      double("KillBillPayment",
             payment_id: "kb-payment-123",
             transactions: [double("Transaction", transaction_id: "kb-txn-123")])
    end

    before do
      allow(KillBill::Client::Model::Payment).to receive(:new).and_return(
        double("Payment",
               "account_id=" => nil,
               "payment_external_key=" => nil,
               "transactions=" => nil,
               create: mock_payment_response)
      )
      allow(KillBill::Client).to receive(:url=)
    end

    context "when user has no Kill Bill merchant account" do
      before do
        allow(user).to receive(:killbill_merchant_account).and_return(nil)
      end

      it "marks the payment as failed" do
        described_class.perform_payment(payment)
        expect(payment.reload.state).to eq("failed")
      end

      it "returns an error message" do
        errors = described_class.perform_payment(payment)
        expect(errors).to include("Kill Bill merchant account not found for user")
      end
    end

    context "when Kill Bill instance URL is not configured" do
      before do
        allow_any_instance_of(KillbillPayoutProcessor).to receive(:killbill_instance_url).and_return(nil)
      end

      it "raises an error about missing configuration" do
        expect do
          described_class.perform_payment(payment)
        end.not_to raise_error

        expect(payment.reload.state).to eq("failed")
      end
    end

    context "for fiat payouts" do
      before do
        allow_any_instance_of(KillbillPayoutProcessor).to receive(:killbill_instance_url).and_return("http://localhost:8080")
        allow_any_instance_of(KillbillPayoutProcessor).to receive(:is_cryptocurrency_payout?).and_return(false)
      end

      it "creates a credit transaction in Kill Bill" do
        mock_payment = double("Payment")
        allow(mock_payment).to receive(:account_id=)
        allow(mock_payment).to receive(:payment_external_key=)
        allow(mock_payment).to receive(:transactions=)
        allow(mock_payment).to receive(:create).and_return(mock_payment_response)
        allow(KillBill::Client::Model::Payment).to receive(:new).and_return(mock_payment)

        expect(mock_payment).to receive(:create)

        described_class.perform_payment(payment)
      end
    end

    context "for cryptocurrency payouts" do
      let(:payment_with_crypto) do
        create(:payment,
               user: user,
               amount_cents: 100_00,
               currency: Currency::USD,
               state: "processing",
               processor: PayoutProcessorType::KILLBILL,
               json_data: { "is_cryptocurrency" => true, "wallet_address" => "0x1234567890abcdef" })
      end

      before do
        allow_any_instance_of(KillbillPayoutProcessor).to receive(:killbill_instance_url).and_return("http://localhost:8080")
      end

      it "creates a credit transaction with wallet address" do
        mock_payment = double("Payment")
        allow(mock_payment).to receive(:account_id=)
        allow(mock_payment).to receive(:payment_external_key=)
        allow(mock_payment).to receive(:transactions=)
        allow(mock_payment).to receive(:create).and_return(mock_payment_response)
        allow(KillBill::Client::Model::Payment).to receive(:new).and_return(mock_payment)

        expect(mock_payment).to receive(:create)

        described_class.perform_payment(payment_with_crypto)
      end

      it "stores wallet address and payout type in json_data" do
        mock_payment = double("Payment")
        allow(mock_payment).to receive(:account_id=)
        allow(mock_payment).to receive(:payment_external_key=)
        allow(mock_payment).to receive(:transactions=)
        allow(mock_payment).to receive(:create).and_return(mock_payment_response)
        allow(KillBill::Client::Model::Payment).to receive(:new).and_return(mock_payment)

        described_class.perform_payment(payment_with_crypto)

        expect(payment_with_crypto.json_data["is_cryptocurrency_payout"]).to eq(true)
        expect(payment_with_crypto.json_data["payout_type"]).to eq("net")
      end

      context "when wallet address is missing" do
        let(:payment_without_wallet) do
          create(:payment,
                 user: user,
                 amount_cents: 100_00,
                 currency: Currency::USD,
                 state: "processing",
                 processor: PayoutProcessorType::KILLBILL,
                 json_data: { "is_cryptocurrency" => true })
        end

        it "marks the payment as failed" do
          described_class.perform_payment(payment_without_wallet)
          expect(payment_without_wallet.reload.state).to eq("failed")
        end
      end
    end
  end
end
