# frozen_string_literal: true

require "spec_helper"
require "shared_examples/authorize_called"
require "shared_examples/sellers_base_controller_concern"
require "inertia_rails/rspec"

describe EmailsController, inertia: true do
  it_behaves_like "inherits from Sellers::BaseController"

  render_views

  let(:seller) { create(:user) }

  include_context "with user signed in as admin for seller"

  describe "GET index" do
    it_behaves_like "authorize called for action", :get, :index do
      let(:record) { Installment }
    end

    it "redirects to the published tab" do
      get :index

      expect(response).to redirect_to("/emails/published")
    end

    it "redirects to the scheduled tab if there are scheduled installments" do
      create(:installment, seller:, ready_to_publish: true)

      get :index

      expect(response).to redirect_to("/emails/scheduled")
    end
  end

  describe "GET published" do
    it_behaves_like "authorize called for action", :get, :published do
      let(:policy_method) { :index? }
      let(:record) { Installment }
    end

    it "returns successful response with Inertia page data" do
      published_installment = create(:installment, seller:, published_at: 1.day.ago)
      draft_installment = create(:installment, seller:, published_at: nil)

      get :published

      expect(response).to be_successful
      expect(inertia.component).to eq("Emails/Published")
      expect(inertia.props[:installments].map { _1[:external_id] }).to eq([published_installment.external_id])
      expect(inertia.props[:installments].map { _1[:external_id] }).not_to include(draft_installment.external_id)
    end
  end

  describe "GET scheduled" do
    it_behaves_like "authorize called for action", :get, :scheduled do
      let(:policy_method) { :index? }
      let(:record) { Installment }
    end

    it "returns successful response with Inertia page data" do
      scheduled_installment = create(:scheduled_installment, seller:)

      get :scheduled

      expect(response).to be_successful
      expect(inertia.component).to eq("Emails/Scheduled")
      expect(inertia.props[:installments].map { _1[:external_id] }).to eq([scheduled_installment.external_id])
    end
  end
end
