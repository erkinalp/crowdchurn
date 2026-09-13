# frozen_string_literal: true

require "spec_helper"

RSpec.describe "CrowdChurn upstream compatibility" do
  describe "persisted product feature flags" do
    it "keeps batch billing and entitlement independent of bundle review visibility" do
      product = Link.new(flags: (1 << 33) | (1 << 34))

      expect(product).to be_batch_billing_enabled
      expect(product).to be_batch_entitlement_enabled
      expect(product).not_to be_hide_bundle_product_reviews

      product.hide_bundle_product_reviews = true

      expect(product.flags & ((1 << 33) | (1 << 34) | (1 << 35))).to eq((1 << 33) | (1 << 34) | (1 << 35))
      product.batch_billing_enabled = false
      expect(product).to be_batch_entitlement_enabled
      expect(product).to be_hide_bundle_product_reviews
    end
  end

  describe "guest experiment identity" do
    let(:signed_cookies) { {} }
    let(:cookies) { instance_double(ActionDispatch::Cookies::CookieJar, signed: signed_cookies) }

    it "reuses the historical signed identity when installing the current cookie" do
      signed_cookies[:ab_test_buyer_id] = "existing-guest"

      expect(VariantPriceService.get_or_create_buyer_cookie(cookies)).to eq("existing-guest")
      expect(signed_cookies.fetch(VariantPriceService::BUYER_VARIANT_COOKIE_NAME)).to include(
        value: "existing-guest", httponly: true
      )
    end

    it "retains the current identity when both cookie generations exist" do
      signed_cookies[:ab_test_buyer_id] = "old-guest"
      signed_cookies[VariantPriceService::BUYER_VARIANT_COOKIE_NAME] = "current-guest"

      expect(VariantPriceService.get_or_create_buyer_cookie(cookies)).to eq("current-guest")
      expect(signed_cookies[VariantPriceService::BUYER_VARIANT_COOKIE_NAME]).to eq("current-guest")
    end

    it "persists the trusted identity through purchase reloads" do
      purchase = create(:free_purchase, buyer_cookie: "guest-assigned-at-checkout")

      expect(purchase.reload.buyer_cookie).to eq("guest-assigned-at-checkout")
    end
  end

  describe "merchant ownership" do
    [
      ["stripe", nil, {}, HolderOfFunds::GUMROAD],
      ["stripe", :seller, {}, HolderOfFunds::STRIPE],
      ["stripe", :seller, { "meta" => { "stripe_connect" => "true" } }, HolderOfFunds::CREATOR],
      ["paypal", :seller, {}, HolderOfFunds::GUMROAD],
      ["killbill", :seller, {}, HolderOfFunds::CREATOR],
    ].each do |processor, owner, metadata, expected_holder|
      it "retains #{expected_holder} funds for #{processor} with #{owner || 'platform'} ownership and #{metadata}" do
        merchant = MerchantAccount.new(
          charge_processor_id: processor,
          user: owner ? build_stubbed(:user) : nil,
          json_data: metadata
        )

        expect(merchant.holder_of_funds).to eq(expected_holder)
        expect(merchant.is_managed_by_gumroad?).to eq(merchant.is_managed_by_operator?)
      end
    end

    it "keeps upstream and operator account lookups compatible" do
      merchant = MerchantAccount.operator("stripe") || create(:merchant_account, user: nil)

      expect(MerchantAccount.operator("stripe")).to eq(merchant)
      expect(MerchantAccount.gumroad("stripe")).to eq(merchant)
    end
  end

  describe "checkout processor parameters" do
    it "permits Kill Bill tokens without exposing purchase attributes" do
      controller = OrdersController.new
      controller.params = ActionController::Parameters.new(
        killbill_payment_method_id: "payment-method",
        killbill_account_id: "buyer-account",
        merchant_account_id: "untrusted-merchant"
      )

      permitted = controller.send(:permitted_order_params)

      expect(permitted[:killbill_payment_method_id]).to eq("payment-method")
      expect(permitted[:killbill_account_id]).to eq("buyer-account")
      expect(permitted).not_to have_key(:merchant_account_id)
    end

    it "does not apply Stripe quotes to a saved Kill Bill payment method" do
      buyer = build(:user, credit_card: CreditCard.new(charge_processor_id: "killbill"))
      service = Purchase::CreateService.new(product: build(:product), params: { purchase: {} }, buyer:)

      expect(service.send(:stripe_quote_components_applicable?)).to eq(false)
    end

    it "allows a new Stripe payment method instead of the buyer's saved Kill Bill method" do
      buyer = build(:user, credit_card: CreditCard.new(charge_processor_id: "killbill"))
      service = Purchase::CreateService.new(
        product: build(:product),
        params: { purchase: {}, stripe_payment_method_id: "pm_new" },
        buyer:
      )

      expect(service.send(:stripe_quote_components_applicable?)).to eq(true)
    end

    it "rejects Stripe quote components when explicit Kill Bill parameters are present" do
      service = Purchase::CreateService.new(
        product: build(:product),
        params: { purchase: {}, killbill_payment_method_id: "payment-method", stripe_payment_method_id: "pm_new" }
      )

      expect(service.send(:stripe_quote_components_applicable?)).to eq(false)
    end
  end

  describe "variant distribution" do
    it "retains count predicates and capacity without replacing the Active Record count query" do
      rule = VariantDistributionRule.new(distribution_type: :count, distribution_value: 3)

      expect(rule).to be_count
      expect(rule.slots_available?(2)).to eq(true)
      expect(rule.slots_available?(3)).to eq(false)
      expect(VariantDistributionRule.count).to eq(0)
    end

    it "retains survey type predicates used by existing response processing" do
      question = SurveyQuestion.new(question_type: :rating_scale)

      expect(question).to be_rating_scale
      expect(question).not_to be_yes_no
    end
  end
end
