# frozen_string_literal: true

require "spec_helper"

describe Api::V2::FundCartItemsController do
  before do
    @user = create(:user, :eligible_for_service_products)
    @app = create(:oauth_application, owner: create(:user))
    @other_user = create(:user)
    @fund_cart_product = create(:fund_cart_product, user: @user)
    @fund_cart = @fund_cart_product.fund_cart
    @target_product = create(:product, user: @other_user)
  end

  describe "GET 'index'" do
    before do
      @item = create(:fund_cart_item, fund_cart: @fund_cart, product: @target_product, state: "pending")
      @action = :index
      @params = { fund_cart_id: @fund_cart.external_id }
    end

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "returns items for the fund cart" do
        get @action, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["items"].length).to eq(1)
        expect(response.parsed_body["items"][0]["id"]).to eq(@item.external_id)
        expect(response.parsed_body["items"][0]["product_name"]).to eq(@target_product.name)
      end
    end

    describe "when fund cart belongs to another user" do
      before do
        other_owner = create(:user, :eligible_for_service_products)
        other_fund_cart = create(:fund_cart_product, user: other_owner).fund_cart
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params = { fund_cart_id: other_fund_cart.external_id, access_token: @token.token }
      end

      it "returns not found" do
        get :index, params: @params
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("not found")
      end
    end
  end

  describe "POST 'create'" do
    before do
      @action = :create
      @params = { fund_cart_id: @fund_cart.external_id, product_id: @target_product.external_id }
    end

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "creates a pending item" do
        expect {
          post @action, params: @params
        }.to change(FundCartItem, :count).by(1)
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["item"]["product_name"]).to eq(@target_product.name)
        expect(response.parsed_body["item"]["state"]).to eq("pending")
      end

      it "rejects same-seller products" do
        own_product = create(:product, user: @user)
        post @action, params: @params.merge(product_id: own_product.external_id)
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("different seller")
      end

      it "rejects fund_cart nesting" do
        other_fund_cart_product = create(:fund_cart_product, user: @other_user)
        post @action, params: @params.merge(product_id: other_fund_cart_product.external_id)
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("fund_cart")
      end

      it "rejects recurring subscriptions" do
        membership = create(:membership_product, user: @other_user)
        post @action, params: @params.merge(product_id: membership.external_id)
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("recurring subscription")
      end

      it "returns not found for nonexistent product" do
        post @action, params: @params.merge(product_id: "nonexistent")
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("not found")
      end
    end
  end

  describe "DELETE 'destroy'" do
    before do
      @item = create(:fund_cart_item, fund_cart: @fund_cart, product: @target_product, state: "pending")
      @action = :destroy
      @params = { fund_cart_id: @fund_cart.external_id, id: @item.external_id }
    end

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "removes a pending item" do
        delete @action, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["message"]).to include("deleted successfully")
        expect(@item.reload.state).to eq("removed")
      end

      it "rejects purchased items" do
        @item.update!(state: "purchased", purchased_at: Time.current)
        delete @action, params: @params
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("pending")
      end

      it "returns not found for missing items" do
        delete @action, params: @params.merge(id: "nonexistent")
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to include("not found")
      end
    end
  end
end
