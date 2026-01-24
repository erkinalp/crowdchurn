# frozen_string_literal: true

require "spec_helper"

describe Subscription, "multi-currency billing" do
  include CurrencyHelper

  let(:seller) { create(:user) }
  let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd") }
  let(:subscription) { create(:subscription, link: product, billing_currency: "usd") }
  let!(:purchase) { create(:purchase, link: product, subscription: subscription, is_original_subscription_purchase: true, displayed_price_cents: 1000) }

  describe "#billing_currency" do
    it "defaults to usd" do
      new_subscription = create(:subscription, link: product)
      expect(new_subscription.billing_currency).to eq("usd")
    end

    it "can be set to other currencies" do
      subscription.update!(billing_currency: "eur")
      expect(subscription.reload.billing_currency).to eq("eur")
    end
  end

  describe "#resolve_subscription_price_for_billing_currency" do
    context "with legacy pricing mode" do
      before { product.update!(pricing_mode: :legacy) }

      it "returns the base price regardless of billing_currency" do
        subscription.update!(billing_currency: "eur")
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(1000)
      end
    end

    context "with gross pricing mode" do
      before { product.update!(pricing_mode: :gross) }

      it "returns the base price when billing_currency matches product currency" do
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(1000)
      end

      it "returns FX-converted price when billing_currency differs" do
        subscription.update!(billing_currency: "eur")
        price = subscription.send(:resolve_subscription_price_for_billing_currency, 1000)
        expect(price).to be_a(Numeric)
        expect(price).not_to eq(1000)
      end
    end

    context "with multi_currency pricing mode" do
      before do
        product.update!(pricing_mode: :multi_currency)
        create(:price, link: product, price_cents: 900, currency: "eur", recurrence: "monthly")
      end

      it "returns the base price when billing_currency matches product currency" do
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(1000)
      end

      it "returns explicit price when available for billing_currency" do
        subscription.update!(billing_currency: "eur")
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(900)
      end

      it "falls back to base price when no explicit price exists for billing_currency" do
        subscription.update!(billing_currency: "gbp")
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(1000)
      end
    end

    context "with nil billing_currency" do
      before do
        product.update!(pricing_mode: :gross)
        subscription.update_column(:billing_currency, nil)
      end

      it "returns the base price" do
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(1000)
      end
    end

    context "with nil link" do
      before do
        product.update!(pricing_mode: :gross)
        subscription.update!(billing_currency: "eur")
        allow(subscription).to receive(:link).and_return(nil)
      end

      it "returns the base price" do
        expect(subscription.send(:resolve_subscription_price_for_billing_currency, 1000)).to eq(1000)
      end
    end
  end

  describe "#current_subscription_price_cents with multi-currency" do
    context "with gross pricing mode" do
      before { product.update!(pricing_mode: :gross) }

      it "returns the base price when billing_currency matches product currency" do
        expect(subscription.current_subscription_price_cents).to eq(1000)
      end

      it "returns FX-converted price when billing_currency differs" do
        subscription.update!(billing_currency: "eur")
        price = subscription.current_subscription_price_cents
        expect(price).to be_a(Numeric)
      end
    end

    context "with multi_currency pricing mode" do
      before do
        product.update!(pricing_mode: :multi_currency)
        create(:price, link: product, price_cents: 900, currency: "eur", recurrence: "monthly")
      end

      it "returns explicit price when available for billing_currency" do
        subscription.update!(billing_currency: "eur")
        expect(subscription.current_subscription_price_cents).to eq(900)
      end
    end
  end
end
