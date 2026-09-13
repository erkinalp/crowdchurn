# frozen_string_literal: true

require "spec_helper"

describe Api::V2::FundCartItemsController do
  before do
    @user = create(:user, :eligible_for_service_products)
    @app = create(:oauth_application, owner: create(:user))
    @other_user = create(:user, :eligible_for_service_products)
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
        @fund_cart.update!(ledger_state: "legacy", ledger_activated_at: nil, activation_evidence: nil)
        get @action, params: @params
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["items"].length).to eq(1)
        expect(response.parsed_body["items"][0]["id"]).to eq(@item.external_id)
        expect(response.parsed_body["items"][0]["product_name"]).to eq(@target_product.name)
        expect(response.parsed_body["items"][0]["route_status"]).to include("state" => "reconciling")
        expect(response.parsed_body["items"][0]["pending_reason"]).to include("code" => "cart_requires_reconciliation")
        expect(response.parsed_body["fund_cart"]).to include("balance_subunits" => 0, "available_subunits" => 0)
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
        expect do
          post @action, params: @params
        end.to change(FundCartItem, :count).by(1)
        expect(response.parsed_body["success"]).to be(true)
        expect(response.parsed_body["item"]["product_name"]).to eq(@target_product.name)
        expect(response.parsed_body["item"]["state"]).to eq("pending")
      end

      it "keeps an unsupported merchant item on the wishlist with an actionable reason" do
        @fund_cart.activate_ledger!
        create(:merchant_account, user: @other_user)

        post @action, params: @params

        expect(response.parsed_body["success"]).to be(true)
        item = response.parsed_body.fetch("item")
        expect(item.fetch("route_status")).to include("state" => "unsupported", "route" => nil)
        expect(item.fetch("pending_reason")).to include("code" => "external_merchant_reservation_unverified")
        expect(item.fetch("pending_reason").fetch("message")).to include("ordinary checkout")
        expect(item.fetch("can_remove")).to be(true)
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

      it "cancels a reserved settlement through the core API before removal" do
        @user.update!(country: "United States", state: "OR", zip_code: "97201")
        @target_product.update!(price_cents: 1000)
        lot = back_fund_cart(@fund_cart, net_subunits: 2000)
        quote = FundCart::QuoteService.new(item: @item).perform
        settlement = FundCart::AllocateFundsService.new(fund_cart: @fund_cart).reserve!(item: @item, quote:)
        expect(FundCart::CancelSettlementService).to receive(:perform).with(settlement: settlement, operation_key: "remove-item:#{settlement.operation_key}").and_call_original

        delete @action, params: @params

        expect(response.parsed_body["success"]).to be(true)
        expect(@item.reload.state).to eq("removed")
        expect(settlement.reload.state).to eq("cancelled")
        expect(lot.reload.available_subunits).to eq(2000)
        expect(lot.reserved_subunits).to eq(0)
        expect(@fund_cart.ledger_entries.sum(:amount_subunits)).to eq(0)
      end

      it "does not remove another cart's item" do
        foreign_cart = create(:fund_cart_product, user: @other_user).fund_cart
        foreign_item = create(:fund_cart_item, fund_cart: foreign_cart)

        delete @action, params: @params.merge(id: foreign_item.external_id)

        expect(response.parsed_body["success"]).to be(false)
        expect(foreign_item.reload.state).to eq("pending")
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
