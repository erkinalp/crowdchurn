# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::Affiliates::ProductsController do
  render_views

  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }
  let(:affiliate_user) { create(:user) }
  let(:product1) { create(:product, name: "Product 1") }
  let(:product2) { create(:product, name: "Product 2") }

  before do
    create(:direct_affiliate, affiliate_user:, products: [product1, product2])
    sign_in admin_user
  end

  describe "GET index" do
    it "returns successful response with Inertia page data" do
      get :index, params: { affiliate_id: affiliate_user.id, page: 1 }

      expect(response).to be_successful
      expect(response.body).to include("data-page")
      expect(response.body).to include("Admin/Affiliates/Products/Index")
    end
  end
end
