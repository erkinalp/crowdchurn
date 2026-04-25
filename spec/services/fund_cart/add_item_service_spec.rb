# frozen_string_literal: true

describe FundCart::AddItemService do
  let(:seller) { create(:user, :eligible_for_service_products) }
  let(:fund_cart_product) { create(:fund_cart_product, user: seller) }
  let(:fund_cart) { fund_cart_product.fund_cart }
  let(:other_seller) { create(:user) }

  describe "#perform" do
    context "with a valid product" do
      let(:product) { create(:product, user: other_seller) }

      it "creates a pending fund cart item" do
        item, error = described_class.new(fund_cart: fund_cart, product: product).perform

        expect(error).to be_nil
        expect(item).to be_persisted
        expect(item.state).to eq("pending")
        expect(item.product).to eq(product)
        expect(item.fund_cart).to eq(fund_cart)
      end
    end

    context "with a product from the same seller" do
      let(:product) { create(:product, user: seller) }

      it "returns an error" do
        item, error = described_class.new(fund_cart: fund_cart, product: product).perform

        expect(item).to be_nil
        expect(error).to eq("Product must be from a different seller")
      end
    end

    context "with a fund_cart product" do
      let(:product) { create(:fund_cart_product, user: other_seller) }

      it "returns an error" do
        item, error = described_class.new(fund_cart: fund_cart, product: product).perform

        expect(item).to be_nil
        expect(error).to eq("Product cannot be a fund_cart product")
      end
    end

    context "with a recurring subscription product" do
      let(:product) { create(:product, user: other_seller, is_recurring_billing: true) }

      it "returns an error" do
        item, error = described_class.new(fund_cart: fund_cart, product: product).perform

        expect(item).to be_nil
        expect(error).to eq("Product cannot be a recurring subscription")
      end
    end
  end
end
