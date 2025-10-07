# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::AffiliatesController do
  render_views

  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }
  let(:affiliate_users) { create_list(:direct_affiliate, 10).map(&:affiliate_user) }
  let(:affiliate_user) { affiliate_users.first }

  before do
    affiliate_users
    sign_in admin_user
  end

  describe "GET index" do
    context "when there's one matching affiliate in search result" do
      let(:single_affiliate_user) { create(:user, email: "unique_affiliate@example.com") }

      before do
        create(:direct_affiliate, affiliate_user: single_affiliate_user)
      end

      it "redirects to affiliate's admin page" do
        get :index, params: { query: single_affiliate_user.email }

        expect(response).to redirect_to admin_affiliate_path(single_affiliate_user)
      end
    end

    context "when there are multiple affiliates in search result" do
      it "returns successful response with Inertia page data" do
        get :index, params: { query: "edgar" }

        expect(response).to be_successful
        expect(response.body).to include("data-page")
        expect(response.body).to include("Admin/Affiliates/Index")
      end

      it "returns JSON response when requested" do
        get :index, params: { query: "edgar" }, format: :json

        expect(response).to be_successful
        expect(response.content_type).to match(%r{application/json})
        expect(response.parsed_body["users"]).to be_present
        expect(response.parsed_body["users"].map { |user| user["id"] }).to match_array(affiliate_users.map(&:external_id))
        expect(response.parsed_body["pagination"]).to be_present
      end

      context "when paginating" do
        before do
          get :index, params: { query: "edgar", page: page, per_page: 5, format: :json }
        end

        context "when on first page" do
          let(:page) { 1 }

          it "paginates results" do
            expect(response).to be_successful
            expect(response.content_type).to match(%r{application/json})
            expect(response.parsed_body["users"]).to be_present
            expect(response.parsed_body["users"].map { |user| user["id"] }).to match_array(affiliate_users.first(5).map(&:external_id))
            expect(response.parsed_body["pagination"]).to be_present
          end
        end

        context "when on second page" do
          let(:page) { 2 }

          it "paginates results" do
            expect(response).to be_successful
            expect(response.content_type).to match(%r{application/json})
            expect(response.parsed_body["users"]).to be_present
            expect(response.parsed_body["users"].map { |user| user["id"] }).to match_array(affiliate_users.last(5).map(&:external_id))
            expect(response.parsed_body["pagination"]).to be_present
          end
        end
      end
    end
  end

  describe "GET show" do
    let(:affiliate_user) { create(:user, name: "Sam") }

    context "when affiliate account is present" do
      before do
        create(:direct_affiliate, affiliate_user:)
      end

      it "returns successful response with Inertia page data" do
        get :show, params: { id: affiliate_user.id }

        expect(response).to be_successful
        expect(response.body).to include("data-page")
        expect(response.body).to include("Admin/Affiliates/Show")
        expect(assigns[:title]).to eq "Sam affiliate on Gumroad"
      end

      it "returns JSON response when requested" do
        get :show, params: { id: affiliate_user.id }, format: :json

        expect(response).to be_successful
        expect(response.content_type).to match(%r{application/json})
      end
    end

    context "when affiliate account is not present" do
      it "raises ActionController::RoutingError" do
        expect do
          get :show, params: { id: affiliate_user.id }
        end.to raise_error(ActionController::RoutingError, "Not Found")
      end
    end
  end
end
