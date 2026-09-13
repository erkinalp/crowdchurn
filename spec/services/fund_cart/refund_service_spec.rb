# frozen_string_literal: true

require "spec_helper"

describe FundCart::RefundService do
  let(:buyer) { create(:user, :eligible_for_service_products, name: "Buyer Example", country: "United States", state: "OR", zip_code: "97201", street_address: "123 Main St", city: "Portland") }
  let(:cart) { create(:fund_cart_product, user: buyer).fund_cart }
  let(:product) { create(:product, price_cents: 1000) }
  let!(:item) { create(:fund_cart_item, fund_cart: cart, product:) }
  let!(:lot) { back_fund_cart(cart, net_subunits: 2000) }
  let(:source) { lot.source_purchase }

  def reserve
    quote = FundCart::QuoteService.new(item: item.reload).perform
    FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
  end

  def settle
    settlement = reserve
    FundCart::SettlementService.new(settlement:).perform
    settlement.reload
  end

  def request_refund(purchase, key:, amount_cents: nil, is_for_fraud: true)
    described_class.new(purchase:).request!(refunding_user_id: purchase.seller_id, amount_cents:, is_for_fraud:, operation_key: key)
    operation = FundCartSettlementOperation.find_by!(operation_key: key)
    FundCartRefundJob.new.perform(operation.id) if operation.state == "pending"
    operation.reload
  end

  def response(amount: source.total_transaction_cents, status: "succeeded", currency: lot.currency, id: "re_fund_cart_test")
    Stripe::Refund.construct_from(id:, object: "refund", charge: lot.source_payment_id, amount:, status:, currency:, metadata: {},
                                  balance_transaction: { id: "txn_#{id}", object: "balance_transaction", source: id, amount: -amount, currency: })
  end

  def source_event(refund)
    ChargeEvent.new.tap do |event|
      event.charge_id = lot.source_payment_id
      event.refund_id = refund.id
      event.charge_processor_id = StripeChargeProcessor.charge_processor_id
      event.extras = { refund_status: refund.status }
    end
  end

  describe "destination refunds" do
    it "routes public partial refunds through a stable operation before ordinary charge checks" do
      purchase = settle.purchase
      expect(purchase.amount_refundable_cents).to eq(1000)
      expect(purchase.refund!(refunding_user_id: purchase.seller_id, amount: 4, operation_key: "public-partial")).to eq(false)
      expect(purchase.fund_cart_refund_pending).to eq(true)
      operation = FundCartSettlementOperation.find_by!(operation_key: "public-partial")
      expect(FundCartRefundJob.jobs.map { |job| job["args"] }).to include([operation.id])
      FundCartOperationJob.new.perform(operation.id)
      expect(operation.reload.state).to eq("completed")
      expect(purchase.reload.amount_refundable_cents).to eq(600)
      2.times { purchase.refund!(refunding_user_id: purchase.seller_id, amount: 4, operation_key: "public-partial") }
      expect(purchase.refunds.count).to eq(1)
      expect(lot.reload.available_subunits).to eq(1400)
    end

    it "requires an explicit identity for a partial refund" do
      purchase = settle.purchase
      expect(purchase.refund!(refunding_user_id: purchase.seller_id, amount: 4)).to eq(false)
      expect(purchase.errors.full_messages.join).to include("partial_refund_operation_key_required")
      expect(purchase.refunds).to be_empty
    end

    it "recovers seller funds before restoring all allocated source funds without submitting a processor refund" do
      settlement = settle
      purchase = settlement.purchase
      expect(Stripe::Refund).not_to receive(:create)
      expect(ChargeProcessor).not_to receive(:refund!)
      operation = request_refund(purchase, key: "destination-full")

      expect(operation.state).to eq("completed")
      expect(purchase.reload).to be_stripe_refunded
      expect(purchase.stripe_transaction_id).to be_nil
      expect(purchase.refunds.sole.processor_refund_id).to be_nil
      expect(purchase.purchase_success_balance.reload.amount_cents).to eq(0)
      expect(lot.reload.available_subunits).to eq(2000)
      expect(lot.spent_subunits).to eq(0)
      expect(settlement.reload.reversed_subunits).to eq(1000)
      expect(operation.ledger_entries.sum(:amount_subunits)).to eq(0)
      expect(operation.external_references["seller_recovery_balance_transaction_id"]).to be_present
    end

    it "supports an exact partial refund followed by a refund of the remainder" do
      purchase = settle.purchase
      first = request_refund(purchase, key: "destination-partial", amount_cents: 333)
      expect(first.state).to eq("completed")
      expect(purchase.reload).to be_stripe_partially_refunded
      expect(lot.reload.available_subunits).to eq(1333)
      expect(lot.spent_subunits).to eq(667)

      last = request_refund(purchase, key: "destination-remainder")
      expect(last.state).to eq("completed")
      expect(purchase.refunds.sum(:total_transaction_cents)).to eq(1000)
      expect(purchase.purchase_success_balance.reload.amount_cents).to eq(0)
      expect(lot.reload.available_subunits).to eq(2000)
    end

    it "does not credit a source when the destination seller's balance was paid or depleted" do
      settlement = settle
      purchase = settlement.purchase
      purchase.purchase_success_balance.update!(amount_cents: 0, holding_amount_cents: 0)
      operation = request_refund(purchase, key: "destination-insufficient")

      expect(operation.state).to eq("reconciling")
      expect(operation.error_code).to eq("destination_seller_recovery_insufficient")
      expect(purchase.reload).not_to be_stripe_refunded
      expect(purchase.refunds).to be_empty
      expect(lot.reload.available_subunits).to eq(1000)
      expect(lot.spent_subunits).to eq(1000)
      expect(operation.ledger_entries).to be_empty
    end

    it "replays a stable partial operation without a second recovery or a second Refund" do
      purchase = settle.purchase
      operation = request_refund(purchase, key: "destination-repeat", amount_cents: 400)
      original_count = purchase.balance_transactions.count
      2.times { request_refund(purchase, key: operation.operation_key, amount_cents: 400) }
      expect(purchase.refunds.count).to eq(1)
      expect(purchase.balance_transactions.count).to eq(original_count)
      expect(lot.reload.available_subunits).to eq(1400)
    end

    it "rejects reuse of an operation identity with a different partial amount" do
      purchase = settle.purchase
      request_refund(purchase, key: "immutable-refund", amount_cents: 400)
      expect(described_class.new(purchase:).request!(refunding_user_id: purchase.seller_id, amount_cents: 500, operation_key: "immutable-refund")).to eq(false)
      expect(purchase.errors.full_messages.join).to include("refund_operation_request_mismatch")
      expect(purchase.refunds.sum(:total_transaction_cents)).to eq(400)
    end
  end

  describe "contribution refunds" do
    it "keeps an accounted partial-refund remainder available" do
      allow(Stripe::Refund).to receive(:create).and_return(response(amount: 500))
      operation = request_refund(source, key: "source-partial-spendable", amount_cents: 500)
      expect(operation.state).to eq("completed")
      expect(source.reload).to be_stripe_partially_refunded
      expect(lot.reload).to be_spendable
      expect(cart.available_subunits).to eq(1600)
      expect(cart.debt_subunits).to eq(0)
    end

    it "recovers a timed-out submission by its metadata without issuing another refund" do
      allow(Stripe::Refund).to receive(:create).and_raise(Stripe::APIConnectionError.new("timeout"))
      operation = request_refund(source, key: "timed-out-refund")
      recovered = response
      recovered.metadata = { fund_cart_operation: operation.operation_key }
      allow(Stripe::Refund).to receive(:list).with(charge: lot.source_payment_id, limit: 100)
        .and_return(Stripe::ListObject.construct_from(object: "list", data: [recovered.to_h], has_more: false))
      allow(Stripe::Refund).to receive(:retrieve).and_return(recovered)
      operation.update!(available_at: 1.minute.ago)
      FundCartRefundJob.clear
      FundCartOutboxJob.new.perform
      expect(FundCartRefundJob.jobs.map { |job| job["args"] }).to include([operation.id])
      FundCartRefundJob.new.perform(operation.id)
      expect(operation.reload.state).to eq("completed")
      expect(source.refunds.count).to eq(1)
      expect(Stripe::Refund).to have_received(:create).once
    end

    it "refunds captured proceeds before asynchronous source confirmation without creating owner debt" do
      pending = restrict_fund_cart_contribution(cart, net_subunits: 2000)
      pending_purchase = pending.source_purchase
      evidence = lot.confirmation_evidence.merge("payment_id" => pending_purchase.stripe_transaction_id,
                                                 "balance_transaction_id" => "txn_pending_source", "availability_verified" => false,
                                                 "available_at" => 2.days.from_now.iso8601)
      allow(FundCart::StripeCustody).to receive(:confirm).with(lot: pending, for_reversal: true).and_return(evidence)
      refunded = response
      refunded.charge = pending_purchase.stripe_transaction_id
      allow(Stripe::Refund).to receive(:create).and_return(refunded)
      operation = request_refund(pending_purchase, key: "source-before-confirmation")
      expect(operation.state).to eq("completed")
      expect(pending.reload.available_subunits).to eq(0)
      expect(pending.reversed_subunits).to eq(2000)
      expect(pending.debt_subunits).to eq(0)
      expect(pending.ledger_entries.sum(:amount_subunits)).to eq(0)
      expect(pending_purchase.refunds.count).to eq(1)
    end

    it "requires provider availability after a partial refund of an unconfirmed source" do
      pending = restrict_fund_cart_contribution(cart, net_subunits: 2000)
      pending_purchase = pending.source_purchase
      evidence = lot.confirmation_evidence.merge("payment_id" => pending_purchase.stripe_transaction_id,
                                                 "balance_transaction_id" => "txn_pending_partial", "availability_verified" => false,
                                                 "available_at" => 2.days.from_now.iso8601)
      allow(FundCart::StripeCustody).to receive(:confirm).with(lot: pending, for_reversal: true).and_return(evidence)
      refunded = response(amount: 500)
      refunded.charge = pending_purchase.stripe_transaction_id
      allow(Stripe::Refund).to receive(:create).and_return(refunded)
      operation = request_refund(pending_purchase, key: "source-pending-partial", amount_cents: 500)
      expect(operation.state).to eq("completed")
      expect(pending.reload.available_subunits).to eq(1600)
      expect(pending).not_to be_spendable
      expect(pending.operations.find_by!(kind: "confirm_source").state).to eq("pending")
      allow(FundCart::StripeCustody).to receive(:confirm).with(lot: pending)
        .and_return(evidence.merge("availability_verified" => true, "available_at" => 1.minute.ago.iso8601))
      FundCart::ContributeService.confirm!(lot: pending)
      expect(pending.reload).to be_spendable
      expect(pending.ledger_entries.where(account: "source_custody").count).to eq(1)
    end

    it "cancels unexecuted reservations before refunding restricted proceeds" do
      settlement = reserve
      allow(Stripe::Refund).to receive(:create).and_return(response)
      operation = request_refund(source, key: "source-unspent")
      expect(operation.state).to eq("completed")
      expect(settlement.reload.state).to eq("cancelled")
      expect(lot.reload.available_subunits).to eq(0)
      expect(lot.reserved_subunits).to eq(0)
      expect(lot.reversed_subunits).to eq(2000)
      expect(lot.debt_subunits).to eq(0)
      expect(source.balance_transactions.where(user_id: buyer.id)).to be_empty
    end

    it "keeps paid destination purchases intact and records only spent shortfall as owner debt" do
      destination = settle.purchase
      allow(Stripe::Refund).to receive(:create).and_return(response)
      operation = request_refund(source, key: "source-spent")
      expect(operation.state).to eq("completed")
      expect(destination.reload).not_to be_stripe_refunded
      expect(destination).to be_funded_by_fund_cart
      expect(lot.reload.available_subunits).to eq(0)
      expect(lot.spent_subunits).to eq(1000)
      expect(lot.debt_subunits).to eq(1000)
      expect(operation.payload["owner_id"]).to eq(buyer.id)
      expect(operation.payload["source_merchant_account_id"]).to eq(lot.source_merchant_account_id)
      expect(operation.ledger_entries.sum(:amount_subunits)).to eq(0)
    end

    it "records a proportional partial source reversal rather than reversing the entire lot" do
      allow(Stripe::Refund).to receive(:create).and_return(response(amount: 625))
      operation = request_refund(source, key: "source-partial", amount_cents: 625)
      expect(operation.state).to eq("completed")
      expect(source.reload).to be_stripe_partially_refunded
      expect(lot.reload.reversed_subunits).to eq(500)
      expect(lot.available_subunits).to eq(1500)
      expect(lot.debt_subunits).to eq(0)
    end

    it "accounts for retained acquiring fees separately without debiting the owner's ordinary seller balance" do
      source.update!(processor_fee_cents: 100, processor_fee_cents_currency: "usd")
      allow(Stripe::Refund).to receive(:create).and_return(response)
      operation = request_refund(source, key: "source-fee", is_for_fraud: false)
      expect(operation.state).to eq("completed")
      expect(operation.refund.retained_fee_cents).to eq(100)
      expect(lot.reload.debt_subunits).to eq(100)
      expect(operation.ledger_entries.where(account: "platform_fee").sum(:amount_subunits)).to eq(100)
      expect(source.balance_transactions.where(user_id: buyer.id)).to be_empty
    end

    it "uses only the original charge and stable idempotency key" do
      expect(Stripe::Refund).to receive(:create).with(hash_including(charge: lot.source_payment_id, amount: 2500), { idempotency_key: "source-route" }).once.and_return(response)
      operation = request_refund(source, key: "source-route")
      FundCartRefundJob.new.perform(operation.id)
      expect(operation.external_references["source_merchant_account_id"]).to eq(lot.source_merchant_account_id)
    end

    it "leaves a timeout frozen and reconciling without resubmitting or claiming completion" do
      expect(Stripe::Refund).to receive(:create).once.and_raise(Stripe::APIConnectionError.new("timeout"))
      operation = request_refund(source, key: "source-timeout")
      FundCartRefundJob.new.perform(operation.id)
      expect(operation.reload.state).to eq("reconciling")
      expect(source.refunds).to be_empty
      expect(lot.reload.state).to eq("frozen")
      expect(cart.available_subunits).to eq(0)
    end

    it "does not turn a pending asynchronous refund into a completed refund" do
      allow(Stripe::Refund).to receive(:create).and_return(response(status: "pending"))
      operation = request_refund(source, key: "source-pending")
      expect(operation.state).to eq("reconciling")
      expect(operation.external_references["processor_refund_id"]).to be_present
      expect(source.refunds).to be_empty
      expect(cart.available_subunits).to eq(0)
    end

    it "unfreezes a canceled pending refund without creating a refund or a fictitious reversal" do
      allow(Stripe::Refund).to receive(:create).and_return(response(status: "pending"))
      operation = request_refund(source, key: "source-canceled-pending")
      canceled = response(status: "canceled")
      allow(Stripe::Refund).to receive(:retrieve).and_return(canceled)
      2.times { source.handle_event_refund_failed!(source_event(canceled)) }
      expect(operation.reload.state).to eq("failed")
      expect(source.refunds).to be_empty
      expect(lot.reload.available_subunits).to eq(2000)
      expect(cart.available_subunits).to eq(2000)
      expect(lot.reversed_subunits).to eq(0)
    end

    it "freezes a processor-initiated refund before a failed provider lookup" do
      external = response(id: "re_external_unknown")
      allow(Stripe::Refund).to receive(:retrieve).and_raise(Stripe::APIConnectionError.new("timeout"))
      expect { source.handle_event_refund_updated!(source_event(external)) }.to raise_error(Stripe::APIConnectionError)
      expect(lot.reload.state).to eq("frozen")
      expect(cart.available_subunits).to eq(0)
      expect(lot.operations.find_by!(operation_key: "source-refund:#{lot.id}:#{external.id}").state).to eq("reconciling")
      expect(source.refunds).to be_empty
    end

    it "defers legacy transaction-bound callbacks while preserving the refund identity for lookup reconciliation" do
      external = response(id: "re_legacy_deferred")
      allow(Stripe::Refund).to receive(:retrieve).and_return(external)
      service = described_class.new(purchase: source)
      ApplicationRecord.transaction do
        expect(service.record_external_refund_id!(processor_refund_id: external.id)).to eq(false)
        expect(Stripe::Refund).not_to have_received(:retrieve)
      end
      operation = lot.operations.find_by!(operation_key: "source-refund:#{lot.id}:#{external.id}")
      expect(operation.state).to eq("reconciling")
      expect(cart.available_subunits).to eq(0)
      service.reconcile!(operation)
      expect(operation.reload.state).to eq("completed")
      expect(Stripe::Refund).to have_received(:retrieve).once
    end

    it "rejects differently denominated provider evidence rather than relabeling it" do
      allow(Stripe::Refund).to receive(:create).and_return(response(currency: "jpy"))
      operation = request_refund(source, key: "source-currency")
      expect(operation.state).to eq("reconciling")
      expect(operation.error_code).to eq("source_refund_evidence_mismatch")
      expect(source.refunds).to be_empty
    end

    %w[failed canceled].each do |status|
      it "restores a subsequently #{status} refund with linked reversible postings exactly once" do
        destination = settle.purchase
        allow(Stripe::Refund).to receive(:create).and_return(response)
        original = request_refund(source, key: "source-#{status}")
        failed = response(status:)
        allow(Stripe::Refund).to receive(:retrieve).and_return(failed)
        2.times { source.handle_event_refund_failed!(source_event(failed)) }

        expect(original.refund.reload.status).to eq(status)
        expect(original.refund.balance_reversed_on_failure).to eq(true)
        expect(source.reload).not_to be_stripe_refunded
        expect(lot.reload.available_subunits).to eq(1000)
        expect(lot.spent_subunits).to eq(1000)
        expect(lot.debt_subunits).to eq(0)
        expect(destination.reload).not_to be_stripe_refunded
        restoration = lot.operations.find_by!(operation_key: "restore:#{original.operation_key}")
        expect(restoration.ledger_entries.pluck(:reversal_of_id)).to match_array(original.ledger_entries.pluck(:id))
        expect(cart.ledger_entries.sum(:amount_subunits)).to eq(0)
      end
    end

    it "reconciles by lookup and makes duplicate success callbacks accounting no-ops" do
      allow(Stripe::Refund).to receive(:create).and_return(response(status: "pending"))
      operation = request_refund(source, key: "source-async-success")
      succeeded = response
      allow(Stripe::Refund).to receive(:retrieve).and_return(succeeded)
      2.times { source.handle_event_refund_updated!(source_event(succeeded)) }
      expect(operation.reload.state).to eq("completed")
      expect(source.refunds.count).to eq(1)
      expect(lot.reload.reversed_subunits).to eq(2000)
    end
  end

  describe "contribution disputes" do
    it "journals a dispute before source confirmation and recovers it without inventing owner debt" do
      pending = restrict_fund_cart_contribution(cart, net_subunits: 2000)
      pending_purchase = pending.source_purchase
      dispute = create(:dispute, purchase: pending_purchase, charge: nil)
      evidence = lot.confirmation_evidence.merge("payment_id" => pending_purchase.stripe_transaction_id,
                                                 "balance_transaction_id" => "txn_disputed_source")
      allow(FundCart::StripeCustody).to receive(:confirm).with(lot: pending, for_reversal: true).and_return(evidence)
      flow = FlowOfFunds.build_simple_flow_of_funds(pending.currency, -pending_purchase.total_transaction_cents)
      expect(described_class.new(purchase: pending_purchase).dispute!(dispute:, flow_of_funds: flow)).to eq(false)
      expect(FundCart::StripeCustody).not_to have_received(:confirm).with(lot: pending, for_reversal: true)
      operation = pending.operations.find_by!(kind: "source_dispute")
      expect(operation.state).to eq("pending")
      FundCartOperationJob.new.perform(operation.id)
      expect(operation.reload.state).to eq("completed")
      expect(pending.reload.reversed_subunits).to eq(2000)
      expect(pending.available_subunits).to eq(0)
      expect(pending.debt_subunits).to eq(0)
      expect(pending.ledger_entries.sum(:amount_subunits)).to eq(0)
    end

    it "dispatches real formalization callbacks without debiting the owner's ordinary seller balance" do
      create(:dispute_formalized, purchase: source, formalized_side_effects_finished_at: nil)
      source.update!(chargeback_date: Time.current, chargeback_reversed: false)
      event = ChargeEvent.new
      event.charge_id = lot.source_payment_id
      event.charge_processor_id = StripeChargeProcessor.charge_processor_id
      event.created_at = Time.current
      event.flow_of_funds = FlowOfFunds.build_simple_flow_of_funds(lot.currency, -source.total_transaction_cents)
      expect(source).not_to receive(:decrement_balance_for_refund_or_chargeback!)
      allow(source).to receive(:create_dispute_evidence_if_needed!)
      2.times { source.reload.handle_event_dispute_formalized!(event) }
      expect(lot.reload.available_subunits).to eq(0)
      expect(lot.reversed_subunits).to eq(2000)
      expect(lot.operations.where(kind: "source_dispute", state: "completed").count).to eq(1)
      expect(source.balance_transactions.where(user_id: buyer.id)).to be_empty
    end

    it "freezes an ambiguously denominated dispute without relabeling settled funds" do
      dispute = create(:dispute_formalized, purchase: source)
      flow = FlowOfFunds.build_simple_flow_of_funds(lot.currency, -source.total_transaction_cents)
      flow.settled_amount = FlowOfFunds::Amount.new(currency: "eur", cents: -source.total_transaction_cents)
      expect { described_class.new(purchase: source).dispute!(dispute:, flow_of_funds: flow) }
        .to raise_error(FundCart::SettlementError, "refund_issued_currency_or_amount_mismatch")
      expect(lot.reload.state).to eq("frozen")
      expect(lot.reversed_subunits).to eq(0)
      expect(lot.debt_subunits).to eq(0)
      expect(cart.available_subunits).to eq(0)
    end

    it "freezes and reverses source proceeds on formalization, and does not debit twice on loss" do
      destination = settle.purchase
      dispute = create(:dispute_formalized, purchase: source)
      source.update!(chargeback_date: Time.current, chargeback_reversed: false)
      service = described_class.new(purchase: source)
      flow = FlowOfFunds.build_simple_flow_of_funds(lot.currency, -source.total_transaction_cents)
      service.dispute!(dispute:, flow_of_funds: flow)
      2.times { service.dispute!(dispute:, flow_of_funds: flow, lost: true) }
      expect(lot.reload.debt_subunits).to eq(1000)
      expect(lot.reversed_subunits).to eq(2000)
      expect(destination.reload).not_to be_stripe_refunded
      expect(lot.operations.where(kind: "source_dispute").count).to eq(1)
    end

    it "restores a dispute win and reverses that restoration once if the dispute later becomes lost" do
      settle
      dispute = create(:dispute_formalized, purchase: source)
      source.update!(chargeback_date: Time.current, chargeback_reversed: false)
      service = described_class.new(purchase: source)
      flow = FlowOfFunds.build_simple_flow_of_funds(lot.currency, -source.total_transaction_cents)
      service.dispute!(dispute:, flow_of_funds: flow)
      source.update!(chargeback_reversed: true)
      won_flow = FlowOfFunds.build_simple_flow_of_funds(lot.currency, source.total_transaction_cents)
      2.times { source.reload.create_credit_for_dispute_won!(won_flow) }
      expect(lot.reload.debt_subunits).to eq(0)
      expect(lot.available_subunits).to eq(1000)
      source.update!(chargeback_reversed: false)
      2.times { service.dispute!(dispute:, flow_of_funds: flow, lost: true) }
      expect(lot.reload.debt_subunits).to eq(1000)
      expect(lot.available_subunits).to eq(0)
      source.update!(chargeback_reversed: true)
      2.times { source.reload.create_credit_for_dispute_won!(won_flow) }
      expect(lot.reload.debt_subunits).to eq(0)
      expect(lot.available_subunits).to eq(1000)
      source.update!(chargeback_reversed: false)
      2.times { service.dispute!(dispute:, flow_of_funds: flow, lost: true) }
      expect(lot.reload.debt_subunits).to eq(1000)
      expect(lot.operations.where(kind: "source_dispute").count).to eq(3)
      expect(cart.ledger_entries.sum(:amount_subunits)).to eq(0)
    end

    it "uses only an authorized destination refund to repay debt and correctly restores a later dispute win" do
      destination = settle.purchase
      dispute = create(:dispute_formalized, purchase: source)
      source.update!(chargeback_date: Time.current, chargeback_reversed: false)
      service = described_class.new(purchase: source)
      service.dispute!(dispute:, flow_of_funds: FlowOfFunds.build_simple_flow_of_funds(lot.currency, -source.total_transaction_cents))
      operation = request_refund(destination, key: "destination-repay-debt")
      expect(operation.state).to eq("completed")
      expect(lot.reload.debt_subunits).to eq(0)
      expect(lot.available_subunits).to eq(0)
      source.update!(chargeback_reversed: true)
      service.dispute_won!(dispute:, flow_of_funds: FlowOfFunds.build_simple_flow_of_funds(lot.currency, source.total_transaction_cents))
      expect(lot.reload.available_subunits).to eq(2000)
      expect(lot.spent_subunits).to eq(0)
      expect(lot.debt_subunits).to eq(0)
      expect(cart.ledger_entries.sum(:amount_subunits)).to eq(0)
    end
  end

  it "preserves ordinary seller refund debits and failed-refund balance restoration" do
    ordinary = create(:purchase, merchant_account: lot.source_merchant_account, stripe_transaction_id: "ch_ordinary_balance")
    ordinary.increment_sellers_balance!
    previous_balance = ordinary.purchase_success_balance.reload.amount_cents
    processor_refund = double("ordinary refund", id: "re_ordinary_balance", status: "succeeded")
    flow = FlowOfFunds.build_simple_flow_of_funds("usd", -ordinary.total_transaction_cents)
    expect(described_class).not_to receive(:new)
    expect(ordinary.refund_purchase!(flow, ordinary.seller_id, processor_refund, true)).to eq(true)
    expect(ordinary.purchase_success_balance.reload.amount_cents).to eq(0)
    refund = ordinary.refunds.sole
    Purchase::HandleFailedRefundService.new(refund:).perform
    expect(refund.reload.balance_reversed_on_failure).to eq(true)
    expect(ordinary.reload).not_to be_stripe_refunded
    expect(ordinary.purchase_success_balance.reload.amount_cents).to eq(previous_balance)
  end

  it "does not dispatch ordinary purchases or their provider callbacks into fund-cart accounting" do
    ordinary = create(:purchase, stripe_transaction_id: "ch_ordinary_unrelated")
    expect(described_class.handles?(ordinary)).to eq(false)
    event = ChargeEvent.new
    event.charge_id = ordinary.stripe_transaction_id
    expect(described_class.handle_event!(event)).to eq(false)
    expect(described_class).not_to receive(:new)
    ordinary.stripe_transaction_id = nil
    expect(ordinary.refund_and_save!(ordinary.seller_id)).to be_nil
  end
end
