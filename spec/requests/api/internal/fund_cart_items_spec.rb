# frozen_string_literal: true

require "spec_helper"

describe Api::Internal::FundCartItemsController, type: :request do
  let(:seller) { create(:user, :eligible_for_service_products) }
  let(:fund_cart_product) { create(:fund_cart_product, user: seller) }
  let(:fund_cart) { fund_cart_product.fund_cart }
  let(:other_seller) { create(:user) }
  let(:target_product) { create(:product, user: other_seller) }

  before do
    sign_in seller
  end

  describe "GET /api/internal/fund_carts/:fund_cart_id/items" do
    let!(:pending_item) { create(:fund_cart_item, fund_cart: fund_cart, product: target_product, state: "pending") }
    let!(:purchased_item) { create(:fund_cart_item, fund_cart: fund_cart, product: create(:product, user: other_seller), state: "purchased", purchased_at: Time.current) }

    it "returns items and balance for the owner" do
      get "/api/internal/fund_carts/#{fund_cart.external_id}/items"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["items"].length).to eq(2)
      expect(body["balance_subunits"]).to eq(fund_cart.balance_subunits)
      expect(body["currency"]).to eq(fund_cart.currency)
    end

    context "when not the owner" do
      before { sign_in other_seller }

      it "rejects the request" do
        get "/api/internal/fund_carts/#{fund_cart.external_id}/items"

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body["error"]).to eq("Unauthorized")
      end
    end

    context "when fund cart not found" do
      it "returns not found" do
        get "/api/internal/fund_carts/nonexistent/items"

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "POST /api/internal/fund_carts/:fund_cart_id/items" do
    it "creates a pending item" do
      expect {
        post "/api/internal/fund_carts/#{fund_cart.external_id}/items", params: { product_id: target_product.external_id }
      }.to change(FundCartItem, :count).by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["item"]["product_name"]).to eq(target_product.name)
      expect(body["item"]["state"]).to eq("pending")
    end

    it "rejects same-seller products" do
      own_product = create(:product, user: seller)

      post "/api/internal/fund_carts/#{fund_cart.external_id}/items", params: { product_id: own_product.external_id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("different seller")
    end

    it "rejects fund_cart nesting" do
      other_fund_cart_product = create(:fund_cart_product, user: other_seller)

      post "/api/internal/fund_carts/#{fund_cart.external_id}/items", params: { product_id: other_fund_cart_product.external_id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("fund_cart")
    end

    it "rejects recurring subscriptions" do
      membership = create(:membership_product, user: other_seller)

      post "/api/internal/fund_carts/#{fund_cart.external_id}/items", params: { product_id: membership.external_id }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("recurring subscription")
    end

    it "rejects when product not found" do
      post "/api/internal/fund_carts/#{fund_cart.external_id}/items", params: { product_id: "nonexistent" }

      expect(response).to have_http_status(:not_found)
    end

    context "when not the owner" do
      before { sign_in other_seller }

      it "rejects the request" do
        post "/api/internal/fund_carts/#{fund_cart.external_id}/items", params: { product_id: target_product.external_id }

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/internal/fund_carts/:fund_cart_id/items/:id" do
    let!(:pending_item) { create(:fund_cart_item, fund_cart: fund_cart, product: target_product, state: "pending") }

    it "removes a pending item" do
      delete "/api/internal/fund_carts/#{fund_cart.external_id}/items/#{pending_item.external_id}"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["success"]).to be(true)
      expect(pending_item.reload.state).to eq("removed")
    end

    it "rejects purchased items" do
      pending_item.update!(state: "purchased", purchased_at: Time.current)

      delete "/api/internal/fund_carts/#{fund_cart.external_id}/items/#{pending_item.external_id}"

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("pending")
    end

    it "returns not found for missing items" do
      delete "/api/internal/fund_carts/#{fund_cart.external_id}/items/nonexistent"

      expect(response).to have_http_status(:not_found)
    end

    context "when not the owner" do
      before { sign_in other_seller }

      it "rejects the request" do
        delete "/api/internal/fund_carts/#{fund_cart.external_id}/items/#{pending_item.external_id}"

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
