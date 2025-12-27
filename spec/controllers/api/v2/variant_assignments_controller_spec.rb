# frozen_string_literal: true

require "spec_helper"
require "shared_examples/authorized_oauth_v1_api_method"

describe Api::V2::VariantAssignmentsController do
  before do
    @user = create(:user)
    @app = create(:oauth_application, owner: create(:user))
    @product = create(:product, user: @user)
    @installment = create(:installment, link: @product, seller: @user)
    @post_variant = create(:post_variant, installment: @installment)
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

      it "returns empty array when no assignments exist" do
        get @action, params: @params
        expect(response.parsed_body["assignments"]).to eq []
      end

      it "returns assignments for the post variant" do
        subscription = create(:subscription, link: @product, user: create(:user))
        assignment = create(:variant_assignment, post_variant: @post_variant, subscription: subscription)
        get @action, params: @params
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["assignments"].length).to eq 1
        expect(response.parsed_body["assignments"][0]["id"]).to eq assignment.external_id
        expect(response.parsed_body["assignments"][0]["subscription_id"]).to eq subscription.external_id
      end

      it "returns error for invalid post_variant_id" do
        get @action, params: @params.merge(post_variant_id: "invalid")
        expect(response.parsed_body).to eq({
          success: false,
          message: "The post_variant was not found."
        }.as_json)
      end

      it "returns error when accessing another user's post variant" do
        other_user = create(:user)
        other_product = create(:product, user: other_user)
        other_installment = create(:installment, link: other_product, seller: other_user)
        other_post_variant = create(:post_variant, installment: other_installment)

        get @action, params: @params.merge(post_variant_id: other_post_variant.external_id)
        expect(response.parsed_body).to eq({
          success: false,
          message: "The post_variant was not found."
        }.as_json)
      end
    end
  end
end
