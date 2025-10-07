# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::ActionCallDashboardController do
  render_views

  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }

  before do
    sign_in admin_user
  end

  describe "GET #show" do
    it "returns successful response with Inertia page data ordered by call_count descending" do
      get :show

      expect(response).to be_successful
      expect(response.body).to include("data-page")
      expect(response.body).to include("Admin/ActionCallDashboard/Show")
    end

    it "returns successful response" do
      get :show

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-page")
    end
  end
end
