# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::Compliance::Guids::UsersController do
  render_views

  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }
  let(:users) { create_list(:user, 4) }
  let(:user1) { users[0] }
  let(:user2) { users[1] }
  let(:user3) { users[2] }
  let(:user4) { users[3] }
  let(:browser_guid) { SecureRandom.uuid }
  let(:other_browser_guid) { SecureRandom.uuid }

  before do
    create_list(:event, 2, user_id: user1.id, browser_guid: browser_guid)
    create_list(:event, 2, user_id: user2.id, browser_guid: browser_guid)
    create_list(:event, 2, user_id: user3.id, browser_guid: browser_guid)
    create_list(:event, 2, user_id: user4.id, browser_guid: other_browser_guid)
    sign_in admin_user
  end

  describe "GET index" do
    it "returns successful response with Inertia page data" do
      get :index, params: { guid_id: browser_guid }

      expect(response).to be_successful
      expect(response.body).to include("data-page")
      expect(response.body).to include("Admin/Compliance/Guids/Users/Index")
    end

    it "returns successful response for JSON format" do
      get :index, params: { guid_id: browser_guid }, format: :json

      expect(response).to be_successful
      expect(response.content_type).to match(%r{application/json})
    end

    it "paginates users correctly" do
      get :index, params: { guid_id: browser_guid, page: 1 }, format: :json

      expect(response).to be_successful
      json_response = JSON.parse(response.body)
      expect(json_response["users"]).to be_present
      expect(json_response["pagination"]).to be_present
    end

    it "includes only users associated with the GUID" do
      other_user = create(:user)
      other_guid = SecureRandom.uuid
      create(:event, user_id: other_user.id, browser_guid: other_guid)

      get :index, params: { guid_id: browser_guid }, format: :json

      expect(response).to be_successful
      json_response = JSON.parse(response.body)
      expect(json_response["users"]).to be_present
      expect(json_response["users"].map { |user| user["id"] }).to match_array([user1.external_id, user2.external_id, user3.external_id])
      expect(json_response["users"].map { |user| user["id"] }).not_to include(user4.external_id)
    end
  end
end
