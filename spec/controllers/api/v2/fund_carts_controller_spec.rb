# frozen_string_literal: true

require "spec_helper"

describe Api::V2::FundCartsController do
  before do
    @user = create(:user, :eligible_for_service_products)
    @app = create(:oauth_application, owner: create(:user))
  end

  describe "GET 'index'" do
    before do
      @fund_cart_product = create(:fund_cart_product, user: @user)
      @fund_cart = @fund_cart_product.fund_cart
      @action = :index
      @params = {}
    end

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "returns the fund carts" do
        get @action, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["fund_carts"].length).to eq(1)
        expect(response.parsed_body["fund_carts"][0]["id"]).to eq(@fund_cart.external_id)
        expect(response.parsed_body["fund_carts"][0]["balance_subunits"]).to eq(0)
      end

      it "does not present a historical counter as spendable" do
        @fund_cart.update!(balance_subunits: 5000)

        get @action, params: @params

        cart = response.parsed_body.fetch("fund_carts").sole
        expect(cart).to include("balance_subunits" => 0, "available_subunits" => 0, "pending_subunits" => 0, "reserved_subunits" => 0, "debt_subunits" => 0, "ledger_state" => "active", "currency" => "usd", "currency_exponent" => 2)
        expect(cart.fetch("amounts").fetch("available")).to eq("subunits" => "0", "currency" => "usd", "currency_exponent" => 2, "formatted" => "0.00 USD")
        expect(@fund_cart.reload.balance_subunits).to eq(5000)
      end

      it "does not return fund carts belonging to other users" do
        other_user = create(:user, :eligible_for_service_products)
        create(:fund_cart_product, user: other_user)

        get @action, params: @params
        expect(response.parsed_body["fund_carts"].length).to eq(1)
      end
    end

    describe "when not authenticated" do
      it "returns unauthorized" do
        get @action, params: @params
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET 'show'" do
    before do
      @fund_cart_product = create(:fund_cart_product, user: @user)
      @fund_cart = @fund_cart_product.fund_cart
      @action = :show
      @params = { id: @fund_cart.external_id }
    end

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "returns the fund cart" do
        get @action, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["fund_cart"]["id"]).to eq(@fund_cart.external_id)
        expect(response.parsed_body["fund_cart"]["product_id"]).to eq(@fund_cart_product.external_id)
        expect(response.parsed_body["fund_cart"]["balance_subunits"]).to eq(0)
        expect(response.parsed_body["fund_cart"]["currency"]).to eq("usd")
      end

      it "returns backed availability and pending confirmation separately" do
        create(:fund_cart_item, fund_cart: @fund_cart)
        back_fund_cart(@fund_cart, net_subunits: 2000)
        restrict_fund_cart_contribution(@fund_cart, net_subunits: 700)

        get @action, params: @params

        expect(response).to have_http_status(:ok)
        cart = response.parsed_body.fetch("fund_cart")
        expect(cart).to include("balance_subunits" => 2000, "available_subunits" => 2000, "pending_subunits" => 700, "reserved_subunits" => 0, "debt_subunits" => 0, "ledger_state" => "active")
        expect(cart.fetch("amounts").fetch("pending")).to include("subunits" => "700", "formatted" => "7.00 USD")
      end

      it "returns not found if the product owner differs from the beneficiary" do
        @fund_cart.update!(user: create(:user))

        get @action, params: @params

        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body).not_to have_key("fund_cart")
      end

      it "returns not found for another user's fund cart" do
        other_user = create(:user, :eligible_for_service_products)
        other_fund_cart = create(:fund_cart_product, user: other_user).fund_cart

        get @action, params: @params.merge(id: other_fund_cart.external_id)
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("not found")
      end

      it "returns not found for nonexistent fund cart" do
        get @action, params: @params.merge(id: "nonexistent")
        expect(response.parsed_body["success"]).to be(false)
      end
    end
  end
end
