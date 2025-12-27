# frozen_string_literal: true

require "spec_helper"
require "shared_examples/authorized_oauth_v1_api_method"

describe Api::V2::PostVariantsController do
  before do
    @user = create(:user)
    @app = create(:oauth_application, owner: create(:user))
  end

  describe "GET 'index'" do
    before do
      @product = create(:product, user: @user)
      @installment = create(:installment, link: @product, seller: @user)
      @action = :index
      @params = {
        link_id: @product.external_id,
        installment_id: @installment.external_id
      }
    end

    it_behaves_like "authorized oauth v1 api method"

    describe "when logged in with view_public scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "view_public")
        @params.merge!(access_token: @token.token)
      end

      it "returns empty array when no post variants exist" do
        get @action, params: @params
        expect(response.parsed_body["post_variants"]).to eq []
      end

      it "returns post variants for the installment" do
        post_variant = create(:post_variant, installment: @installment)
        get @action, params: @params
        expect(response.parsed_body).to eq({
          success: true,
          post_variants: [post_variant]
        }.as_json)
      end
    end
  end

  describe "POST 'create'" do
    before do
      @product = create(:product, user: @user)
      @installment = create(:installment, link: @product, seller: @user)
      @action = :create
      @params = {
        link_id: @product.external_id,
        installment_id: @installment.external_id,
        name: "Variant A",
        message: "Test message content"
      }
    end

    it_behaves_like "authorized oauth v1 api method"
    it_behaves_like "authorized oauth v1 api method only for edit_products scope"

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "creates a new post variant" do
        expect do
          post @action, params: @params
        end.to change { @installment.post_variants.count }.by(1)

        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["post_variant"]["name"]).to eq "Variant A"
        expect(response.parsed_body["post_variant"]["message"]).to eq "Test message content"
      end

      it "creates a control variant when is_control is true" do
        post @action, params: @params.merge(is_control: true)
        expect(response.parsed_body["post_variant"]["is_control"]).to be true
      end

      it "returns error when name is missing" do
        post @action, params: @params.except(:name)
        expect(response.parsed_body["success"]).to be false
        expect(response.parsed_body["message"]).to include("Name")
      end

      it "returns error when message is missing" do
        post @action, params: @params.except(:message)
        expect(response.parsed_body["success"]).to be false
        expect(response.parsed_body["message"]).to include("Message")
      end
    end
  end

  describe "GET 'show'" do
    before do
      @product = create(:product, user: @user)
      @installment = create(:installment, link: @product, seller: @user)
      @post_variant = create(:post_variant, installment: @installment)
      @action = :show
      @params = {
        link_id: @product.external_id,
        installment_id: @installment.external_id,
        id: @post_variant.external_id
      }
    end

    it_behaves_like "authorized oauth v1 api method"

    describe "when logged in with view_public scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "view_public")
        @params.merge!(access_token: @token.token)
      end

      it "returns the post variant" do
        get @action, params: @params
        expect(response.parsed_body).to eq({
          success: true,
          post_variant: @post_variant
        }.as_json)
      end

      it "returns error for invalid id" do
        get @action, params: @params.merge(id: "invalid")
        expect(response.parsed_body).to eq({
          success: false,
          message: "The post_variant was not found."
        }.as_json)
      end
    end
  end

  describe "PUT 'update'" do
    before do
      @product = create(:product, user: @user)
      @installment = create(:installment, link: @product, seller: @user)
      @post_variant = create(:post_variant, installment: @installment, name: "Original", message: "Original message")
      @action = :update
      @params = {
        link_id: @product.external_id,
        installment_id: @installment.external_id,
        id: @post_variant.external_id,
        name: "Updated",
        message: "Updated message"
      }
    end

    it_behaves_like "authorized oauth v1 api method"
    it_behaves_like "authorized oauth v1 api method only for edit_products scope"

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "updates the post variant" do
        put @action, params: @params
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["post_variant"]["name"]).to eq "Updated"
        expect(response.parsed_body["post_variant"]["message"]).to eq "Updated message"
      end

      it "returns error for invalid id" do
        put @action, params: @params.merge(id: "invalid")
        expect(response.parsed_body).to eq({
          success: false,
          message: "The post_variant was not found."
        }.as_json)
      end
    end
  end

  describe "DELETE 'destroy'" do
    before do
      @product = create(:product, user: @user)
      @installment = create(:installment, link: @product, seller: @user)
      @post_variant = create(:post_variant, installment: @installment)
      @action = :destroy
      @params = {
        link_id: @product.external_id,
        installment_id: @installment.external_id,
        id: @post_variant.external_id
      }
    end

    it_behaves_like "authorized oauth v1 api method"
    it_behaves_like "authorized oauth v1 api method only for edit_products scope"

    describe "when logged in with edit_products scope" do
      before do
        @token = create("doorkeeper/access_token", application: @app, resource_owner_id: @user.id, scopes: "edit_products")
        @params.merge!(access_token: @token.token)
      end

      it "deletes the post variant" do
        expect do
          delete @action, params: @params
        end.to change { @installment.post_variants.count }.by(-1)

        expect(response.parsed_body).to eq({
          success: true,
          message: "The post_variant was deleted successfully."
        }.as_json)
      end

      it "returns error for invalid id" do
        delete @action, params: @params.merge(id: "invalid")
        expect(response.parsed_body).to eq({
          success: false,
          message: "The post_variant was not found."
        }.as_json)
      end
    end
  end
end
