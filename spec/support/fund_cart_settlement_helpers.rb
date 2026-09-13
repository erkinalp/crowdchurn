# frozen_string_literal: true

module FundCartSettlementHelpers
  def restrict_fund_cart_contribution(cart, net_subunits:)
    cart.activate_ledger! unless cart.ledger_active?
    operator = MerchantAccount.operator(StripeChargeProcessor.charge_processor_id) || create(:merchant_account, user: nil, charge_processor_merchant_id: "acct_fund_cart_test")
    purchase = create(:purchase, :with_custom_fee,
                      link: cart.link, price_cents: net_subunits + 500, fee_cents: 500, purchase_state: "in_progress",
                      displayed_price_currency_type: cart.currency, merchant_account: operator)
    expect(Currency.base).to eq("usd")
    expect(purchase.displayed_price_currency_type.to_s).to eq(cart.currency)
    purchase.increment_sellers_balance!
    purchase.update!(purchase_state: "successful")
    FundCart::ContributeService.new(purchase:).perform
    purchase.fund_cart_funding_lot.reload
  end

  def back_fund_cart(cart, net_subunits:)
    lot = restrict_fund_cart_contribution(cart, net_subunits:)
    evidence = {
      "payment_id" => lot.source_purchase.stripe_transaction_id, "balance_transaction_id" => "txn_#{lot.id}",
      "currency" => lot.currency, "currency_exponent" => lot.currency_exponent, "custody_key" => lot.custody_key,
      "source_gross_subunits" => lot.gross_subunits.to_i, "source_net_subunits" => lot.net_subunits.to_i,
      "available_at" => 1.day.ago.iso8601, "confirmed_at" => Time.current.iso8601
    }
    allow(FundCart::StripeCustody).to receive(:confirm).with(lot:).and_return(evidence)
    FundCart::ContributeService.confirm!(lot:)
    lot.reload
  end
end

RSpec.configure do |config|
  config.include FundCartSettlementHelpers
end
