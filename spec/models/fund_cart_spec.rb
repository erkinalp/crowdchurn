# frozen_string_literal: true

describe FundCart do
  describe "validations" do
    it "validates presence of currency" do
      fund_cart = build(:fund_cart, currency: nil)
      expect(fund_cart).to be_invalid
      expect(fund_cart.errors.full_messages).to include("Currency can't be blank")
    end

    it "validates currency matches the link's currency" do
      product = create(:fund_cart_product)
      fund_cart = build(:fund_cart, link: product, currency: "eur")
      expect(fund_cart).to be_invalid
      expect(fund_cart.errors.full_messages).to include("Currency must match the product's currency")
    end

    it "is valid with matching currency" do
      product = create(:fund_cart_product)
      fund_cart = build(:fund_cart, link: product, user: product.user, currency: product.price_currency_type)
      expect(fund_cart).to be_valid
    end
  end

  describe "#pending_items" do
    let(:seller) { create(:user, :eligible_for_service_products) }
    let(:fund_cart_product) { create(:fund_cart_product, user: seller) }
    let(:fund_cart) { fund_cart_product.fund_cart }

    let(:other_seller_1) { create(:user) }
    let(:other_seller_2) { create(:user) }
    let(:other_seller_3) { create(:user) }

    it "returns only pending items sorted by price descending" do
      expensive_product = create(:product, user: other_seller_1, price_cents: 5000)
      cheap_product = create(:product, user: other_seller_2, price_cents: 1000)

      expensive_item = create(:fund_cart_item, fund_cart: fund_cart, product: expensive_product)
      cheap_item = create(:fund_cart_item, fund_cart: fund_cart, product: cheap_product)
      create(:fund_cart_item, fund_cart: fund_cart, product: create(:product, user: other_seller_3, price_cents: 3000), state: "purchased")

      result = fund_cart.pending_items
      expect(result.map(&:id)).to eq([expensive_item.id, cheap_item.id])
    end

    it "breaks ties by type priority (digital before physical before bundle)" do
      digital_product = create(:product, user: other_seller_1, price_cents: 1000, native_type: "digital")
      physical_product = create(:product, user: other_seller_2, price_cents: 1000, native_type: "physical")

      physical_item = create(:fund_cart_item, fund_cart: fund_cart, product: physical_product)
      digital_item = create(:fund_cart_item, fund_cart: fund_cart, product: digital_product)

      result = fund_cart.pending_items
      expect(result.map(&:id)).to eq([digital_item.id, physical_item.id])
    end
  end
end
