# frozen_string_literal: true

require "spec_helper"

describe Killbill::SetupIntentsController do
  let(:user) { create(:user) }
  let(:killbill_account) do
    double(
      "KillBill::Client::Model::Account",
      account_id: "kb-account-123",
      external_key: "gumroad_user_#{user.id}"
    )
  end
  let(:payment_method) do
    double(
      "KillBill::Client::Model::PaymentMethod",
      payment_method_id: "kb-pm-456",
      account_id: "kb-account-123",
      is_default: true,
      plugin_name: "killbill-stripe",
      plugin_info: { "properties" => [{ "key" => "last4", "value" => "4242" }] }
    )
  end

  before do
    sign_in user
  end

  describe "POST create" do
    context "when user is not authenticated" do
      before { sign_out user }

      it "redirects to login" do
        post :create, params: {}

        expect(response).to redirect_to(login_path(next: "/killbill/setup_intents"))
      end
    end

    context "when Kill Bill account exists" do
      before do
        allow(KillBill::Client::Model::Account).to receive(:find_by_external_key)
          .and_return(killbill_account)
        allow(KillBill::Client::Model::PaymentMethod).to receive(:new)
          .and_return(payment_method)
        allow(payment_method).to receive(:account_id=)
        allow(payment_method).to receive(:plugin_name=)
        allow(payment_method).to receive(:plugin_info=)
        allow(payment_method).to receive(:is_default=)
        allow(payment_method).to receive(:create).and_return(payment_method)
      end

      it "creates a payment method and returns success" do
        post :create, params: { card_number: "4242424242424242", card_expiry_month: "12", card_expiry_year: "2030" }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to eq(true)
        expect(response.parsed_body["payment_method_id"]).to eq("kb-pm-456")
        expect(response.parsed_body["account_id"]).to eq("kb-account-123")
      end
    end

    context "when Kill Bill account does not exist" do
      let(:new_account) do
        double(
          "KillBill::Client::Model::Account",
          account_id: "kb-new-account-789",
          external_key: "gumroad_user_#{user.id}"
        )
      end

      before do
        allow(KillBill::Client::Model::Account).to receive(:find_by_external_key)
          .and_raise(KillBill::Client::API::NotFound.new(nil))
        allow(KillBill::Client::Model::Account).to receive(:new).and_return(new_account)
        allow(new_account).to receive(:external_key=)
        allow(new_account).to receive(:name=)
        allow(new_account).to receive(:email=)
        allow(new_account).to receive(:currency=)
        allow(new_account).to receive(:create).and_return(new_account)
        allow(KillBill::Client::Model::PaymentMethod).to receive(:new)
          .and_return(payment_method)
        allow(payment_method).to receive(:account_id=)
        allow(payment_method).to receive(:plugin_name=)
        allow(payment_method).to receive(:plugin_info=)
        allow(payment_method).to receive(:is_default=)
        allow(payment_method).to receive(:create).and_return(payment_method)
      end

      it "creates a new account and payment method" do
        post :create, params: { card_number: "4242424242424242" }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to eq(true)
        expect(response.parsed_body["account_id"]).to eq("kb-new-account-789")
      end
    end

    context "when creating a cryptocurrency payment method" do
      before do
        allow(KillBill::Client::Model::Account).to receive(:find_by_external_key)
          .and_return(killbill_account)
        allow(KillBill::Client::Model::PaymentMethod).to receive(:new)
          .and_return(payment_method)
        allow(payment_method).to receive(:account_id=)
        allow(payment_method).to receive(:plugin_name=)
        allow(payment_method).to receive(:plugin_info=)
        allow(payment_method).to receive(:is_default=)
        allow(payment_method).to receive(:create).and_return(payment_method)
      end

      it "stores wallet_address and is_cryptocurrency properties" do
        expect(payment_method).to receive(:plugin_info=) do |info|
          properties = info[:properties]
          wallet_prop = properties.find { |p| p[:key] == "wallet_address" }
          crypto_prop = properties.find { |p| p[:key] == "is_cryptocurrency" }

          expect(wallet_prop[:value]).to eq("0x1234567890abcdef")
          expect(crypto_prop[:value]).to eq("true")
        end

        post :create, params: {
          wallet_address: "0x1234567890abcdef",
          cryptocurrency_type: "ETH"
        }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to eq(true)
      end

      it "uses killbill-crypto plugin for cryptocurrency payment methods" do
        expect(payment_method).to receive(:plugin_name=).with("killbill-crypto")

        post :create, params: {
          wallet_address: "0x1234567890abcdef"
        }

        expect(response).to be_successful
      end
    end

    context "when payment method creation fails" do
      before do
        allow(KillBill::Client::Model::Account).to receive(:find_by_external_key)
          .and_return(killbill_account)
        allow(KillBill::Client::Model::PaymentMethod).to receive(:new)
          .and_return(payment_method)
        allow(payment_method).to receive(:account_id=)
        allow(payment_method).to receive(:plugin_name=)
        allow(payment_method).to receive(:plugin_info=)
        allow(payment_method).to receive(:is_default=)
        allow(payment_method).to receive(:create).and_return(nil)
      end

      it "returns an error response" do
        post :create, params: {}

        expect(response).to be_unprocessable
        expect(response.parsed_body["success"]).to eq(false)
        expect(response.parsed_body["error_message"]).to eq("Failed to create payment method.")
      end
    end

    context "when ChargeProcessorUnavailableError occurs" do
      before do
        allow(KillBill::Client::Model::Account).to receive(:find_by_external_key)
          .and_raise(ChargeProcessorUnavailableError.new("Kill Bill unavailable"))
      end

      it "returns a service unavailable error" do
        post :create, params: {}

        expect(response).to be_server_error
        expect(response.parsed_body["success"]).to eq(false)
        expect(response.parsed_body["error_message"]).to include("temporary problem")
      end
    end

    context "when Kill Bill API returns bad request" do
      before do
        allow(KillBill::Client::Model::Account).to receive(:find_by_external_key)
          .and_raise(KillBill::Client::API::BadRequest.new(nil))
      end

      it "returns an unprocessable entity error" do
        post :create, params: {}

        expect(response).to be_unprocessable
        expect(response.parsed_body["success"]).to eq(false)
        expect(response.parsed_body["error_message"]).to include("Invalid payment method data")
      end
    end
  end

  describe "GET show" do
    context "when user is not authenticated" do
      before { sign_out user }

      it "redirects to login" do
        get :show, params: { id: "kb-pm-456" }

        expect(response).to redirect_to(login_path(next: "/killbill/setup_intents/kb-pm-456"))
      end
    end

    context "when payment method exists" do
      before do
        allow(KillBill::Client::Model::PaymentMethod).to receive(:find_by_id)
          .and_return(payment_method)
      end

      it "returns payment method details" do
        get :show, params: { id: "kb-pm-456" }

        expect(response).to be_successful
        expect(response.parsed_body["success"]).to eq(true)
        expect(response.parsed_body["payment_method_id"]).to eq("kb-pm-456")
        expect(response.parsed_body["account_id"]).to eq("kb-account-123")
        expect(response.parsed_body["is_default"]).to eq(true)
        expect(response.parsed_body["plugin_name"]).to eq("killbill-stripe")
      end

      it "only returns safe plugin info properties" do
        crypto_payment_method = double(
          "KillBill::Client::Model::PaymentMethod",
          payment_method_id: "kb-pm-crypto",
          account_id: "kb-account-123",
          is_default: true,
          plugin_name: "killbill-crypto",
          plugin_info: {
            "properties" => [
              { "key" => "last4", "value" => "4242" },
              { "key" => "card_number", "value" => "4242424242424242" },
              { "key" => "wallet_address", "value" => "0x123" },
              { "key" => "is_cryptocurrency", "value" => "true" }
            ]
          }
        )
        allow(KillBill::Client::Model::PaymentMethod).to receive(:find_by_id)
          .and_return(crypto_payment_method)

        get :show, params: { id: "kb-pm-crypto" }

        plugin_info = response.parsed_body["plugin_info"]
        keys = plugin_info.map { |p| p["key"] }

        expect(keys).to include("last4", "wallet_address", "is_cryptocurrency")
        expect(keys).not_to include("card_number")
      end
    end

    context "when payment method does not exist" do
      before do
        allow(KillBill::Client::Model::PaymentMethod).to receive(:find_by_id)
          .and_raise(KillBill::Client::API::NotFound.new(nil))
      end

      it "returns a not found error" do
        get :show, params: { id: "nonexistent" }

        expect(response).to be_not_found
        expect(response.parsed_body["success"]).to eq(false)
        expect(response.parsed_body["error_message"]).to eq("Payment method not found.")
      end
    end
  end
end
