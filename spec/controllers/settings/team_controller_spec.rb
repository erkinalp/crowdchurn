# frozen_string_literal: true

require "spec_helper"
require "shared_examples/sellers_base_controller_concern"
require "shared_examples/authorize_called"
require "inertia_rails/rspec"

describe Settings::TeamController, type: :controller, inertia: true do
  it_behaves_like "inherits from Sellers::BaseController"

  let(:seller) { create(:named_seller) }

  include_context "with user signed in as admin for seller"

  it_behaves_like "authorize called for controller", Settings::Team::UserPolicy do
    let(:record) { seller }
  end

  describe "GET show" do
    it "returns http success and renders Inertia component" do
      get :show

      expect(response).to be_successful
      expect(inertia.component).to eq("Settings/Team")
      expect(inertia.props).to be_present
      expect(inertia.props[:member_infos]).to be_present
      expect(inertia.props[:settings_pages]).to be_present
    end

    context "when user does not have an email" do
      before do
        seller.update!(
          provider: :twitter,
          twitter_user_id: "123",
          email: nil
        )
      end

      it "redirects" do
        get :show

        expect(response).to redirect_to(settings_main_url)
        expect(flash[:alert]).to eq("Your Gumroad account doesn't have an email associated. Please assign and verify your email, and try again.")
      end
    end
  end
end
