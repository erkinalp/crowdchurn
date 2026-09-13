# frozen_string_literal: true

require "spec_helper"

describe "Subscription fee compatibility" do
  let(:seller) { create(:user, tier_state: User::Tier::TIER_3) }
  let(:product) { create(:subscription_product, user: seller) }
  let(:subscription) { create(:subscription, link: product) }

  it "enables flat fees for newly created subscriptions" do
    expect(subscription.reload.flat_fee_applicable?).to be(true)
  end

  it "preserves the persisted legacy fee flag when an existing subscription is saved" do
    subscription.update!(flat_fee_applicable: false)
    subscription.touch

    expect(subscription.reload.flat_fee_applicable?).to be(false)
  end

  it "keeps merchant-specific legacy rates for a subscription without the flat-fee flag" do
    subscription.update!(flat_fee_applicable: false)
    operator_account = MerchantAccount.operator(StripeChargeProcessor.charge_processor_id) || create(:merchant_account, user: nil)
    connected_account = create(:merchant_account_stripe_connect, user: seller)
    purchase = build(:purchase_in_progress, link: product, seller:, subscription:, merchant_account: operator_account, price_cents: 10_000)

    expect(purchase.send(:calculate_operator_fee_per_thousand)).to eq(30)
    expect(purchase.operator_percentage_fee_cents).to eq(10)

    purchase.merchant_account = connected_account
    purchase.send(:calculate_fees)
    expect(purchase.send(:calculate_operator_fee_per_thousand)).to eq(10)
    expect(purchase.operator_percentage_fee_cents).to eq(100)
  end
end
