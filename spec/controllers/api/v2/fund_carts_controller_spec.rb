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
