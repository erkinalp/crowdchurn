# frozen_string_literal: true

require "spec_helper"
require "shared_examples/admin_base_controller_concern"

describe Admin::UsersController do
  render_views

  it_behaves_like "inherits from Admin::BaseController"

  let(:admin_user) { create(:admin_user) }
  let(:user) { create(:user) }
  let(:product) { create(:product, user:) }

  before do
    sign_in admin_user
  end

  describe "GET 'verify'" do
    let(:request_params) { { id: user.id } }

    it "successfully verifies and unverifies users" do
      expect(user.verified).to be_nil
      get :verify, params: request_params
      expect(response.parsed_body["success"]).to be(true)
      expect(user.reload.verified).to be(true)

      get :verify, params: request_params
      expect(response.parsed_body["success"]).to be(true)
      expect(user.reload.verified).to be(false)
    end

    context "when error is raised" do
      before do
        user
        allow_any_instance_of(User).to receive(:save!).and_raise("Error!")
      end

      it "rescues and returns error message" do
        get :verify, params: request_params

        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq("Error!")
      end
    end
  end

  describe "GET show" do
    let(:user) { create(:user) }

    it "returns successful response with Inertia page data" do
      get :show, params: { id: user.id }

      expect(response).to be_successful
      expect(response.body).to include("data-page")
      expect(response.body).to include("Admin/Users/Show")
    end

    it "returns page successfully when using email" do
      get :show, params: { id: user.email }

      expect(response).to be_successful
      expect(response.body).to include("data-page")
    end

    it "returns page successfully when using username" do
      user.update!(username: "testuser")

      get :show, params: { id: user.username }

      expect(response).to be_successful
      expect(response.body).to include("data-page")
    end

    it "returns page successfully when using external_id" do
      get :show, params: { id: user.external_id }

      expect(response).to be_successful
      expect(response.body).to include("data-page")
    end

    it "returns JSON response when requested" do
      get :show, params: { id: user.id }, format: :json

      expect(response).to be_successful
      expect(response.content_type).to match(%r{application/json})
    end
  end

  describe "refund balance logic", :vcr, :sidekiq_inline do
    describe "POST 'refund_balance'" do
      let(:merchant_account) { create(:merchant_account, user: user) }
      let(:purchase) { create(:purchase, link: product, purchase_state: "in_progress", chargeable: create(:chargeable), merchant_account:) }

      before do
        create(:merchant_account, user: nil)

        stripe_account = double("Stripe::Account", id: "acct_test_gumroad")
        allow(Stripe::Account).to receive(:retrieve).and_return(stripe_account)

        stripe_transfer = double("Stripe::Transfer", id: "tr_test_transfer")
        allow(Stripe::Transfer).to receive(:create).and_return(stripe_transfer)

        purchase.process!
        purchase.increment_sellers_balance!
        purchase.mark_successful!
      end

      it "refunds user's purchases if the user is suspended" do
        user.flag_for_fraud(author_id: admin_user.id)
        user.suspend_for_fraud(author_id: admin_user.id)
        post :refund_balance, params: { id: user.id }
        expect(purchase.reload.stripe_refunded).to be(true)
      end

      it "does not refund user's purchases if the user is not suspended" do
        post :refund_balance, params: { id: user.id }
        expect(purchase.reload.stripe_refunded).to_not be(true)
      end
    end
  end

  describe "POST 'add_credit'" do
    let(:credit_amount) { "100" }
    let(:request_params) { { id: user.id, credit: { credit_amount: credit_amount } } }

    before do
      # Create the Gumroad merchant account that credits are issued against
      create(:merchant_account, user: nil)
    end

    it "successfully creates a credit" do
      expect { post :add_credit, params: request_params }.to change { Credit.count }.from(0).to(1)
      expect(Credit.last.amount_cents).to eq(10_000)
      expect(Credit.last.user).to eq(user)
    end

    it "creates a credit always associated with a gumroad merchant account" do
      create(:merchant_account, user: user)
      user.reload
      post :add_credit, params: request_params
      expect(Credit.last.merchant_account).to eq(MerchantAccount.gumroad(StripeChargeProcessor.charge_processor_id))
      expect(Credit.last.balance.merchant_account).to eq(MerchantAccount.gumroad(StripeChargeProcessor.charge_processor_id))
    end

    context "when credit amount is small" do
      let(:credit_amount) { ".04" }

      it "successfully creates credits even with smaller amounts" do
        expect { post :add_credit, params: request_params }.to change { Credit.count }.from(0).to(1)
        expect(Credit.last.amount_cents).to eq(4)
        expect(Credit.last.user).to eq(user)
      end

      it "sends notification to user" do
        mail_double = double
        allow(mail_double).to receive(:deliver_later)
        expect(ContactingCreatorMailer).to receive(:credit_notification).with(user.id, 4).and_return(mail_double)
        post :add_credit, params: request_params
      end
    end
  end

  describe "POST #mark_compliant" do
    it "marks the user as compliant" do
      post :mark_compliant, params: { id: user.id }
      expect(response).to be_successful
      expect(user.reload.user_risk_state).to eq "compliant"
    end

    it "creates a comment when marking compliant" do
      freeze_time do
        expect do
          post :mark_compliant, params: { id: user.id }
        end.to change(user.comments, :count).by(1)

        comment = user.comments.last
        expect(comment).to have_attributes(
          comment_type: Comment::COMMENT_TYPE_COMPLIANT,
          content: "Marked compliant by #{admin_user.username} on #{Time.current.strftime('%B %-d, %Y')}",
          author: admin_user
        )
      end
    end
  end

  describe "POST #set_custom_fee" do
    let(:custom_fee_percent) { "2.5" }
    let(:request_params) { { id: user.id, custom_fee_percent: custom_fee_percent } }

    it "sets the custom fee for the user" do
      post :set_custom_fee, params: request_params

      expect(response).to be_successful
      expect(user.reload.custom_fee_per_thousand).to eq 25
    end

    context "when custom fee parameter negative" do
      let(:custom_fee_percent) { "-5" }

      it "returns error since custom fee parameter is invalid" do
        post :set_custom_fee, params: request_params
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq("Validation failed: Custom fee per thousand must be greater than or equal to 0")
        expect(user.reload.custom_fee_per_thousand).to be_nil
      end
    end

    context "when custom fee parameter is greater than 100" do
      let(:custom_fee_percent) { "101" }

      it "returns error since custom fee parameter is invalid" do
        post :set_custom_fee, params: request_params
        expect(response.parsed_body["success"]).to be(false)
        expect(response.parsed_body["message"]).to eq("Validation failed: Custom fee per thousand must be less than or equal to 1000")
        expect(user.reload.custom_fee_per_thousand).to be_nil
      end
    end

    context "when custom fee parameter is valid" do
      let(:custom_fee_percent) { "5" }

      before do
        user.update!(custom_fee_per_thousand: 75)
      end

      it "updates the existing custom fee" do
        expect(user.reload.custom_fee_per_thousand).to eq 75
        post :set_custom_fee, params: request_params
        expect(response).to be_successful
        expect(user.reload.custom_fee_per_thousand).to eq 50
      end
    end


  end

  describe "POST #toggle_adult_products" do
    context "when all_adult_products is false" do
      before do
        user.update!(all_adult_products: false)
      end

      it "toggles all_adult_products to true" do
        post :toggle_adult_products, params: { id: user.id }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(true)
        expect(user.reload.all_adult_products).to be(true)
      end
    end

    context "when all_adult_products is true" do
      before do
        user.update!(all_adult_products: true)
      end

      it "toggles all_adult_products to false" do
        post :toggle_adult_products, params: { id: user.id }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(true)
        expect(user.reload.all_adult_products).to be(false)
      end
    end

    context "when all_adult_products is nil" do
      before do
        user.update!(all_adult_products: nil)
      end

      it "toggles all_adult_products to true" do
        post :toggle_adult_products, params: { id: user.id }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(true)
        expect(user.reload.all_adult_products).to be(true)
      end
    end

    context "when user is found by email" do
      it "toggles all_adult_products successfully" do
        user.update!(all_adult_products: false)

        post :toggle_adult_products, params: { id: user.email }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(true)
        expect(user.reload.all_adult_products).to be(true)
      end
    end

    context "when user is found by username" do
      it "toggles all_adult_products successfully" do
        user.update!(all_adult_products: false, username: "testuser")

        post :toggle_adult_products, params: { id: user.username }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to be(true)
        expect(user.reload.all_adult_products).to be(true)
      end
    end
  end
end
