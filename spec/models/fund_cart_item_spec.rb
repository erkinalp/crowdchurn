# frozen_string_literal: true

describe FundCartItem do
  let(:seller) { create(:user, :eligible_for_service_products) }
  let(:fund_cart_product) { create(:fund_cart_product, user: seller) }
  let(:fund_cart) { fund_cart_product.fund_cart }
  let(:other_seller) { create(:user) }

  describe "validations" do
    it "validates state inclusion" do
      item = build(:fund_cart_item, fund_cart: fund_cart, state: "invalid")
      expect(item).to be_invalid
      expect(item.errors.full_messages).to include("State is not included in the list")
    end

    it "validates product is not from the same seller" do
      same_seller_product = create(:product, user: seller)
      item = build(:fund_cart_item, fund_cart: fund_cart, product: same_seller_product)
      expect(item).to be_invalid
      expect(item.errors.full_messages).to include("Product must be from a different seller")
    end

    it "validates product is not a fund_cart" do
      other_fund_cart_product = create(:fund_cart_product, user: other_seller)
      item = build(:fund_cart_item, fund_cart: fund_cart, product: other_fund_cart_product)
      expect(item).to be_invalid
      expect(item.errors.full_messages).to include("Product cannot be a fund_cart product")
    end

    it "validates product is not a recurring subscription" do
      subscription_product = create(:product, user: other_seller, is_recurring_billing: true)
      item = build(:fund_cart_item, fund_cart: fund_cart, product: subscription_product)
      expect(item).to be_invalid
      expect(item.errors.full_messages).to include("Product cannot be a recurring subscription")
    end

    it "validates product currency matches fund cart currency" do
      eur_product = create(:product, user: other_seller, price_currency_type: "eur")
      item = build(:fund_cart_item, fund_cart: fund_cart, product: eur_product)
      expect(item).to be_invalid
      expect(item.errors.full_messages).to include("Product must be priced in the same currency as the fund cart")
    end

    it "is valid with a product from another seller that is not fund_cart or recurring" do
      valid_product = create(:product, user: other_seller)
      item = build(:fund_cart_item, fund_cart: fund_cart, product: valid_product)
      expect(item).to be_valid
    end
  end

  describe "#mark_purchased!" do
    it "updates state to purchased with purchase reference and timestamp" do
      product = create(:product, user: other_seller)
      item = create(:fund_cart_item, fund_cart: fund_cart, product: product)
      purchase = create(:purchase, link: product)

      item.mark_purchased!(purchase)

      expect(item.reload.state).to eq("purchased")
      expect(item.purchase).to eq(purchase)
      expect(item.purchased_at).to be_present
    end
  end

  describe "#mark_removed!" do
    it "updates state to removed" do
      product = create(:product, user: other_seller)
      item = create(:fund_cart_item, fund_cart: fund_cart, product: product)

      item.mark_removed!

      expect(item.reload.state).to eq("removed")
    end
  end

  describe "scopes" do
    let(:product_1) { create(:product, user: other_seller, price_cents: 1000) }
    let(:product_2) { create(:product, user: create(:user), price_cents: 2000) }

    it ".pending returns only pending items" do
      pending_item = create(:fund_cart_item, fund_cart: fund_cart, product: product_1, state: "pending")
      create(:fund_cart_item, fund_cart: fund_cart, product: product_2, state: "purchased")

      expect(fund_cart.fund_cart_items.pending).to eq([pending_item])
    end

    it ".purchased returns only purchased items" do
      create(:fund_cart_item, fund_cart: fund_cart, product: product_1, state: "pending")
      purchased_item = create(:fund_cart_item, fund_cart: fund_cart, product: product_2, state: "purchased")

      expect(fund_cart.fund_cart_items.purchased).to eq([purchased_item])
    end
  end
end
