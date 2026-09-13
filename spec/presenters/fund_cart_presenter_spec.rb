# frozen_string_literal: true

require "spec_helper"

describe FundCartPresenter do
  describe ".amount" do
    it "keeps exact cryptocurrency subunits above JavaScript's safe integer limit" do
      expect(described_class.amount(subunits: 1_234_567_890_123_456_789, currency: "eth")).to eq(
        subunits: "1234567890123456789", currency: "eth", currency_exponent: 18, formatted: "1.234567890123456789 ETH"
      )
    end

    it "preserves single-unit product currencies" do
      expect(described_class.amount(subunits: 1234, currency: "jpy")).to eq(
        subunits: "1234", currency: "jpy", currency_exponent: 0, formatted: "1234 JPY"
      )
    end

    it "uses the recorded monetary exponent when supplied instead of relabeling a snapshot" do
      expect(described_class.amount(subunits: 1234, currency: "jpy", currency_exponent: 2)).to eq(
        subunits: "1234", currency: "jpy", currency_exponent: 2, formatted: "12.34 JPY"
      )
    end
  end

  describe "#item_props" do
    let(:owner) { create(:user, :eligible_for_service_products, country: "United States", state: "OR", zip_code: "97201") }
    let(:cart) { create(:fund_cart_product, user: owner).fund_cart }
    let(:product) { create(:product, price_cents: 1000) }
    let!(:item) { create(:fund_cart_item, fund_cart: cart, product:) }
    let(:presenter) { described_class.new(cart) }

    it "does not manufacture route support or a settlement for a legacy cart" do
      cart.update!(ledger_state: "legacy", ledger_activated_at: nil, activation_evidence: nil)
      props = presenter.item_props(item)

      expect(props[:settlement]).to be_nil
      expect(props[:route_status]).to include(state: "reconciling", route: nil)
      expect(props[:pending_reason][:code]).to eq("cart_requires_reconciliation")
      expect(props[:can_remove]).to be(true)
      expect(props[:can_request_cancellation]).to be(false)
    end

    it "exposes a reservation total and cancellation state without leaking custody or buyer details" do
      back_fund_cart(cart, net_subunits: 2000)
      quote = FundCart::QuoteService.new(item:).perform
      settlement = FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
      settlement.update!(state: "reconciling", cancel_requested_at: Time.current, blocking_reason: "source_backing_unavailable")

      props = presenter.item_props(item.reload)

      expect(props[:settlement]).to eq(
        id: settlement.external_id, state: "reconciling", cancel_requested: true,
        amount: { subunits: "1000", currency: "usd", currency_exponent: 2, formatted: "10.00 USD" }
      )
      expect(props[:pending_reason][:code]).to eq("settlement_cancellation_requested")
      expect(props[:can_remove]).to be(false)
      expect(props[:can_request_cancellation]).to be(false)
      expect(props[:route_status][:state]).to eq("reconciling")
      expect(props[:route_status][:reason][:code]).to eq("source_backing_unavailable")
      expect(props[:route_status][:reason][:message]).to include("Funds remain reserved")
      expect(props.to_json).not_to include("custody_key", "quote_snapshot", owner.email, "merchant_account_id")
    end

    it "retains the paid total after the product price changes" do
      back_fund_cart(cart, net_subunits: 2000)
      quote = FundCart::QuoteService.new(item:).perform
      settlement = FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
      FundCart::SettlementService.new(settlement:).perform
      product.update!(price_cents: 2500)

      props = presenter.item_props(item.reload)

      expect(props[:product_price_cents]).to eq(2500)
      expect(props[:settlement][:amount][:subunits]).to eq("1000")
      expect(props[:pending_reason]).to be_nil
      expect(props[:can_remove]).to be(false)
    end
  end
end
