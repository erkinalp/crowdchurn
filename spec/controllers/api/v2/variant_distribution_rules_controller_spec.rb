# frozen_string_literal: true

require "spec_helper"
require "shared_examples/authorized_oauth_v1_api_method"

describe Api::V2::VariantDistributionRulesController do
  before do
    @user = create(:user)
    @app = create(:oauth_application, owner: create(:user))
    @product = create(:product, user: @user)
    @installment = create(:installment, link: @product, seller: @user)
    @post_variant = create(:post_variant, installment: @installment)
    @variant_category = create(:variant_category, link: @product)
    @base_variant = create(:variant, variant_category: @variant_category)
  end

  describe "GET 'index'" do
    before do
      @action = :index
      @params = {
        post_variant_id: @post_variant.external_id
      }
    end

    it_behaves_like "authorized oauth v1 api method"

    describe "when logged in with view_public scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "view_public")
        @params.merge!(access_token: @token.token)
      end

      it "returns empty array when no distribution rules exist" do
        get @action, params: @params
        expect(response.parsed_body["distribution_rules"]).to eq []
      end

      it "returns distribution rules for the post variant" do
        distribution_rule = create(:variant_distribution_rule, post_variant: @post_variant, base_variant: @base_variant)
        get @action, params: @params
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["distribution_rules"].length).to eq 1
        expect(response.parsed_body["distribution_rules"][0]["id"]).to eq distribution_rule.external_id
      end
    end
  end

  describe "POST 'create'" do
    before do
      @action = :create
      @params = {
        post_variant_id: @post_variant.external_id,
        base_variant_id: @base_variant.external_id,
        distribution_type: "percentage",
        distribution_value: 50
      }
    end

    it_behaves_like "authorized oauth v1 api method"
    it_behaves_like "authorized oauth v1 api method only for edit_products scope"

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "creates a new distribution rule with percentage type" do
        expect do
          post @action, params: @params
        end.to change { @post_variant.variant_distribution_rules.count }.by(1)

        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["distribution_rule"]["distribution_type"]).to eq "percentage"
        expect(response.parsed_body["distribution_rule"]["distribution_value"]).to eq 50
      end

      it "creates a new distribution rule with count type" do
        post @action, params: @params.merge(distribution_type: "count", distribution_value: 100)
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["distribution_rule"]["distribution_type"]).to eq "count"
        expect(response.parsed_body["distribution_rule"]["distribution_value"]).to eq 100
      end

      it "creates a new distribution rule with unlimited type" do
        post @action, params: @params.merge(distribution_type: "unlimited", distribution_value: nil)
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["distribution_rule"]["distribution_type"]).to eq "unlimited"
      end

      it "returns error when distribution_type is missing" do
        post @action, params: @params.except(:distribution_type)
        expect(response.parsed_body["success"]).to be false
      end
    end
  end

  describe "PUT 'update'" do
    before do
      @distribution_rule = create(:variant_distribution_rule, post_variant: @post_variant, base_variant: @base_variant, distribution_type: :percentage, distribution_value: 30)
      @action = :update
      @params = {
        post_variant_id: @post_variant.external_id,
        id: @distribution_rule.external_id,
        distribution_value: 70
      }
    end

    it_behaves_like "authorized oauth v1 api method"
    it_behaves_like "authorized oauth v1 api method only for edit_products scope"

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "updates the distribution rule" do
        put @action, params: @params
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["distribution_rule"]["distribution_value"]).to eq 70
      end

      it "returns error for invalid id" do
        put @action, params: @params.merge(id: "invalid")
        expect(response.parsed_body).to eq({
          success: false,
          message: "The distribution_rule was not found."
        }.as_json)
      end
    end
  end

  describe "DELETE 'destroy'" do
    before do
      @distribution_rule = create(:variant_distribution_rule, post_variant: @post_variant, base_variant: @base_variant)
      @action = :destroy
      @params = {
        post_variant_id: @post_variant.external_id,
        id: @distribution_rule.external_id
      }
    end

    it_behaves_like "authorized oauth v1 api method"
    it_behaves_like "authorized oauth v1 api method only for edit_products scope"

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "deletes the distribution rule" do
        expect do
          delete @action, params: @params
        end.to change { @post_variant.variant_distribution_rules.count }.by(-1)

        expect(response.parsed_body).to eq({
          success: true,
          message: "The distribution_rule was deleted successfully."
        }.as_json)
      end

      it "returns error for invalid id" do
        delete @action, params: @params.merge(id: "invalid")
        expect(response.parsed_body).to eq({
          success: false,
          message: "The distribution_rule was not found."
        }.as_json)
      end
    end
  end
end
