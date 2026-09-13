# frozen_string_literal: true

require "spec_helper"

describe "Kill Bill SDK compatibility" do
  it "keeps transaction requests and refreshes isolated to each merchant's instance and tenant" do
    expect(KillBillClient).not_to receive(:url=)
    processor = KillbillChargeProcessor.new
    chargeable = KillbillChargeablePaymentMethod.new("payment-method", account_id: "buyer-account")

    %w[example.org example.net].each do |host|
      merchant = instance_double(
        MerchantAccount,
        killbill_instance_url: "https://#{host}",
        killbill_username: "merchant-user",
        killbill_password: "merchant-password",
        killbill_api_key: host,
        killbill_api_secret: "#{host}-secret"
      )
      headers = { "X-Killbill-Apikey" => host, "X-Killbill-Apisecret" => "#{host}-secret" }
      payment_url = "https://#{host}/1.0/kb/payments/payment-id"
      post_request = stub_request(:post, "https://#{host}/1.0/kb/accounts/buyer-account/payments")
        .with(query: { "paymentMethodId" => "payment-method" }, headers:) do |request|
          body = JSON.parse(request.body)
          body["amount"] == 12.34 && body["transactionType"] == "PURCHASE" &&
            body["paymentExternalKey"] == "reference"
        end
        .to_return(status: 201, headers: { "Location" => payment_url, "Content-Type" => "application/json" })
      get_request = stub_request(:get, payment_url).with(headers:).to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { paymentId: "payment-id", transactions: [{ status: "PENDING" }] }.to_json
      )

      intent = processor.create_payment_intent_or_charge!(merchant, chargeable, 1234, 34, "reference", "SDK contract")

      expect(intent.id).to eq("payment-id")
      expect(post_request).to have_been_requested
      expect(get_request).to have_been_requested
    end
  end
end
