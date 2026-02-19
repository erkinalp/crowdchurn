# frozen_string_literal: true

describe FundCart::ContributeService do
  let(:seller) { create(:user, :eligible_for_service_products) }
  let(:fund_cart_product) { create(:fund_cart_product, user: seller, price_cents: 0, customizable_price: true) }
  let(:fund_cart) { fund_cart_product.fund_cart }

  describe "#perform" do
    it "adds the purchase amount to the fund cart balance" do
      purchase = create(:purchase, link: fund_cart_product, price_cents: 5000)

      expect do
        described_class.new(purchase: purchase).perform
      end.to change { fund_cart.reload.balance_cents }.from(0).to(5000)
    end

    it "accumulates balance from multiple contributions" do
      purchase_1 = create(:purchase, link: fund_cart_product, price_cents: 3000)
      purchase_2 = create(:purchase, link: fund_cart_product, price_cents: 2000)

      described_class.new(purchase: purchase_1).perform
      described_class.new(purchase: purchase_2).perform

      expect(fund_cart.reload.balance_cents).to eq(5000)
    end

    it "returns early when fund cart is not found" do
      product_without_cart = create(:product)
      purchase = create(:purchase, link: product_without_cart, price_cents: 1000)

      expect { described_class.new(purchase: purchase).perform }.not_to raise_error
    end
  end
end
