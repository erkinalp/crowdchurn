# frozen_string_literal: true

describe FundCart::AllocateFundsService do
  let(:seller) { create(:user, :eligible_for_service_products) }
  let(:fund_cart_product) { create(:fund_cart_product, user: seller) }
  let(:fund_cart) { fund_cart_product.fund_cart }

  let(:other_seller_1) { create(:user) }
  let(:other_seller_2) { create(:user) }

  describe "#perform" do
    context "with sufficient balance for the most expensive item" do
      it "purchases the most expensive item first" do
        expensive_product = create(:product, user: other_seller_1, price_cents: 3000)
        cheap_product = create(:product, user: other_seller_2, price_cents: 1000)

        expensive_item = create(:fund_cart_item, fund_cart: fund_cart, product: expensive_product)
        cheap_item = create(:fund_cart_item, fund_cart: fund_cart, product: cheap_product)

        fund_cart.update!(balance_subunits: 3000)

        described_class.new(fund_cart: fund_cart).perform

        expect(expensive_item.reload.state).to eq("purchased")
        expect(expensive_item.purchase).to be_present
        expect(cheap_item.reload.state).to eq("pending")
        expect(fund_cart.reload.balance_subunits).to eq(0)
      end
    end

    context "with sufficient balance for multiple items" do
      it "purchases multiple items" do
        product_1 = create(:product, user: other_seller_1, price_cents: 2000)
        product_2 = create(:product, user: other_seller_2, price_cents: 1000)

        item_1 = create(:fund_cart_item, fund_cart: fund_cart, product: product_1)
        item_2 = create(:fund_cart_item, fund_cart: fund_cart, product: product_2)

        fund_cart.update!(balance_subunits: 5000)

        described_class.new(fund_cart: fund_cart).perform

        expect(item_1.reload.state).to eq("purchased")
        expect(item_2.reload.state).to eq("purchased")
        expect(fund_cart.reload.balance_subunits).to eq(2000)
      end
    end

    context "with insufficient balance for any item" do
      it "does not purchase any items" do
        product = create(:product, user: other_seller_1, price_cents: 5000)
        item = create(:fund_cart_item, fund_cart: fund_cart, product: product)

        fund_cart.update!(balance_subunits: 1000)

        described_class.new(fund_cart: fund_cart).perform

        expect(item.reload.state).to eq("pending")
        expect(fund_cart.reload.balance_subunits).to eq(1000)
      end
    end

    context "when balance covers a cheaper item but not the most expensive" do
      it "skips the expensive item and purchases the cheaper one" do
        expensive_product = create(:product, user: other_seller_1, price_cents: 5000)
        cheap_product = create(:product, user: other_seller_2, price_cents: 1000)

        expensive_item = create(:fund_cart_item, fund_cart: fund_cart, product: expensive_product)
        cheap_item = create(:fund_cart_item, fund_cart: fund_cart, product: cheap_product)

        fund_cart.update!(balance_subunits: 2000)

        described_class.new(fund_cart: fund_cart).perform

        expect(expensive_item.reload.state).to eq("pending")
        expect(cheap_item.reload.state).to eq("purchased")
        expect(fund_cart.reload.balance_subunits).to eq(1000)
      end
    end

    context "with equally priced items of different types" do
      it "purchases digital items before physical items" do
        digital_product = create(:product, user: other_seller_1, price_cents: 1000, native_type: "digital")
        physical_product = create(:product, user: other_seller_2, price_cents: 1000, native_type: "physical")

        physical_item = create(:fund_cart_item, fund_cart: fund_cart, product: physical_product)
        digital_item = create(:fund_cart_item, fund_cart: fund_cart, product: digital_product)

        fund_cart.update!(balance_subunits: 1000)

        described_class.new(fund_cart: fund_cart).perform

        expect(digital_item.reload.state).to eq("purchased")
        expect(physical_item.reload.state).to eq("pending")
        expect(fund_cart.reload.balance_subunits).to eq(0)
      end
    end

    context "with no pending items" do
      it "does nothing" do
        fund_cart.update!(balance_subunits: 5000)

        expect { described_class.new(fund_cart: fund_cart).perform }.not_to raise_error
        expect(fund_cart.reload.balance_subunits).to eq(5000)
      end
    end

    context "with zero-price items" do
      it "skips zero-price items" do
        free_product = create(:product, user: other_seller_1, price_cents: 0)
        item = create(:fund_cart_item, fund_cart: fund_cart, product: free_product)

        fund_cart.update!(balance_subunits: 5000)

        described_class.new(fund_cart: fund_cart).perform

        expect(item.reload.state).to eq("pending")
        expect(fund_cart.reload.balance_subunits).to eq(5000)
      end
    end
  end
end
