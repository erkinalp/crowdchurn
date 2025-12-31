# frozen_string_literal: true

require "spec_helper"

describe Api::V2::PostVariantsController do
  let(:seller) { create(:user) }
  let(:product) { create(:product, user: seller) }
  let(:app) { create(:oauth_application, owner: create(:user)) }
  let!(:post) { create(:installment, :published, link: product, name: "Test Post") }

  describe "GET 'index'" do
    let(:action) { :index }
    let(:params) { { link_id: product.external_id, post_id: post.external_id } }

    context "when logged in with public scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "view_public") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      context "when post has variants" do
        let!(:variant_a) { create(:post_variant, installment: post, name: "Control", is_control: true) }
        let!(:variant_b) { create(:post_variant, installment: post, name: "Treatment") }

        it "returns all variants" do
          get action, params: params
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["success"]).to be true
          expect(response.parsed_body["post_variants"].length).to eq(2)
        end
      end
    end
  end

  describe "GET 'metrics'" do
    let(:action) { :metrics }
    let(:params) { { link_id: product.external_id, post_id: post.external_id } }

    context "when logged in with public scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "view_public") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      context "when post has no variants" do
        it "returns empty metrics" do
          get action, params: params
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["success"]).to be true
          expect(response.parsed_body["metrics"]["variants"]).to eq([])
          expect(response.parsed_body["metrics"]["totals"]["exposure_count"]).to eq(0)
          expect(response.parsed_body["metrics"]["totals"]["conversion_count"]).to eq(0)
          expect(response.parsed_body["metrics"]["totals"]["conversion_rate"]).to eq(0.0)
        end
      end

      context "when post has variants with assignments" do
        let!(:variant_a) { create(:post_variant, installment: post, name: "Control", is_control: true, price_cents: 1000) }
        let!(:variant_b) { create(:post_variant, installment: post, name: "Treatment", price_cents: 800) }

        let!(:assignment_a1) { create(:variant_assignment, post_variant: variant_a, subscription: create(:subscription), exposed_at: Time.current, converted_at: Time.current) }
        let!(:assignment_a2) { create(:variant_assignment, post_variant: variant_a, subscription: create(:subscription), exposed_at: Time.current, converted_at: nil) }
        let!(:assignment_a3) { create(:variant_assignment, post_variant: variant_a, subscription: create(:subscription), exposed_at: nil, converted_at: nil) }

        let!(:assignment_b1) { create(:variant_assignment, post_variant: variant_b, subscription: create(:subscription), exposed_at: Time.current, converted_at: Time.current) }
        let!(:assignment_b2) { create(:variant_assignment, post_variant: variant_b, subscription: create(:subscription), exposed_at: Time.current, converted_at: Time.current) }
        let!(:assignment_b3) { create(:variant_assignment, post_variant: variant_b, subscription: create(:subscription), exposed_at: Time.current, converted_at: nil) }

        it "returns correct metrics for each variant" do
          get action, params: params
          expect(response).to have_http_status(:ok)
          expect(response.parsed_body["success"]).to be true

          metrics = response.parsed_body["metrics"]
          expect(metrics["post_id"]).to eq(post.external_id)

          variant_a_metrics = metrics["variants"].find { |v| v["name"] == "Control" }
          expect(variant_a_metrics["id"]).to eq(variant_a.external_id)
          expect(variant_a_metrics["is_control"]).to be true
          expect(variant_a_metrics["price_cents"]).to eq(1000)
          expect(variant_a_metrics["assignments_count"]).to eq(3)
          expect(variant_a_metrics["exposure_count"]).to eq(2)
          expect(variant_a_metrics["conversion_count"]).to eq(1)
          expect(variant_a_metrics["conversion_rate"]).to eq(50.0)

          variant_b_metrics = metrics["variants"].find { |v| v["name"] == "Treatment" }
          expect(variant_b_metrics["id"]).to eq(variant_b.external_id)
          expect(variant_b_metrics["is_control"]).to be false
          expect(variant_b_metrics["price_cents"]).to eq(800)
          expect(variant_b_metrics["assignments_count"]).to eq(3)
          expect(variant_b_metrics["exposure_count"]).to eq(3)
          expect(variant_b_metrics["conversion_count"]).to eq(2)
          expect(variant_b_metrics["conversion_rate"]).to eq(66.67)
        end

        it "returns correct totals" do
          get action, params: params

          totals = response.parsed_body["metrics"]["totals"]
          expect(totals["exposure_count"]).to eq(5)
          expect(totals["conversion_count"]).to eq(3)
          expect(totals["conversion_rate"]).to eq(60.0)
        end
      end

      context "when variants have no exposures" do
        let!(:variant_a) { create(:post_variant, installment: post, name: "Control", is_control: true) }
        let!(:assignment) { create(:variant_assignment, post_variant: variant_a, subscription: create(:subscription), exposed_at: nil, converted_at: nil) }

        it "returns 0 conversion rate" do
          get action, params: params

          variant_metrics = response.parsed_body["metrics"]["variants"].first
          expect(variant_metrics["exposure_count"]).to eq(0)
          expect(variant_metrics["conversion_count"]).to eq(0)
          expect(variant_metrics["conversion_rate"]).to eq(0.0)
        end
      end
    end

    context "when post does not exist" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "view_public") }
      let(:params) { { link_id: product.external_id, post_id: "nonexistent", format: :json, access_token: token.token } }

      it "returns error" do
        get action, params: params
        expect(response.parsed_body["success"]).to be false
        expect(response.parsed_body["message"]).to eq("The post was not found.")
      end
    end
  end

  describe "POST 'create'" do
    let(:action) { :create }
    let(:params) { { link_id: product.external_id, post_id: post.external_id, name: "New Variant", message: "Test message" } }

    context "when logged in with edit_products scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "edit_products") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      it "creates a new variant" do
        expect { post action, params: params }.to change { PostVariant.count }.by(1)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["post_variant"]["name"]).to eq("New Variant")
      end

      it "creates a variant with price_cents" do
        params[:price_cents] = 1500
        post action, params: params
        expect(response.parsed_body["post_variant"]["price_cents"]).to eq(1500)
      end
    end
  end

  describe "GET 'show'" do
    let(:action) { :show }
    let!(:variant) { create(:post_variant, installment: post, name: "Test Variant") }
    let(:params) { { link_id: product.external_id, post_id: post.external_id, id: variant.external_id } }

    context "when logged in with public scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "view_public") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      it "returns the variant" do
        get action, params: params
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["post_variant"]["name"]).to eq("Test Variant")
      end
    end
  end

  describe "PUT 'update'" do
    let(:action) { :update }
    let!(:variant) { create(:post_variant, installment: post, name: "Original Name") }
    let(:params) { { link_id: product.external_id, post_id: post.external_id, id: variant.external_id, name: "Updated Name" } }

    context "when logged in with edit_products scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "edit_products") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      it "updates the variant" do
        put action, params: params
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["success"]).to be true
        expect(response.parsed_body["post_variant"]["name"]).to eq("Updated Name")
        expect(variant.reload.name).to eq("Updated Name")
      end
    end
  end

  describe "DELETE 'destroy'" do
    let(:action) { :destroy }
    let!(:variant) { create(:post_variant, installment: post, name: "To Delete") }
    let(:params) { { link_id: product.external_id, post_id: post.external_id, id: variant.external_id } }

    context "when logged in with edit_products scope" do
      let(:token) { create("doorkeeper/access_token", application: app, resource_owner_id: seller.id, scopes: "edit_products") }

      before do
        params.merge!(format: :json, access_token: token.token)
      end

      it "deletes the variant" do
        expect { delete action, params: params }.to change { PostVariant.count }.by(-1)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["success"]).to be true
      end
    end
  end
end
