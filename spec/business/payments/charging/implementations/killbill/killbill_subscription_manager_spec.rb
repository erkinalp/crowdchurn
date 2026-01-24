# frozen_string_literal: true

require "spec_helper"

describe KillbillSubscriptionManager do
  include CurrencyHelper

  let(:seller) { create(:user) }
  let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd") }
  let(:subscription) { create(:subscription, link: product, billing_currency: "usd") }

  let(:mock_account) do
    double(
      "KillBill::Client::Model::Account",
      account_id: "test-account-id",
      email: "test@example.com",
      currency: "USD"
    )
  end

  let(:account_class) { class_double("KillBill::Client::Model::Account").as_stubbed_const }

  describe "#resolve_account_currency" do
    subject { described_class.new }

    context "when subscription has billing_currency set" do
      let(:subscription) { create(:subscription, link: product, billing_currency: "eur") }

      it "returns the subscription's billing_currency in uppercase" do
        currency = subject.send(:resolve_account_currency, subscription)
        expect(currency).to eq("EUR")
      end
    end

    context "when subscription has no billing_currency but link has price_currency_type" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "gbp") }
      let(:subscription) { create(:subscription, link: product, billing_currency: nil) }

      before do
        subscription.update_column(:billing_currency, nil)
      end

      it "returns the product's price_currency_type in uppercase" do
        currency = subject.send(:resolve_account_currency, subscription)
        expect(currency).to eq("GBP")
      end
    end

    context "when neither billing_currency nor price_currency_type is set" do
      let(:subscription) { create(:subscription, link: product, billing_currency: nil) }

      before do
        subscription.update_column(:billing_currency, nil)
        allow(subscription).to receive(:link).and_return(nil)
      end

      it "falls back to USD" do
        currency = subject.send(:resolve_account_currency, subscription)
        expect(currency).to eq("USD")
      end
    end

    context "with different currencies" do
      %w[jpy cad aud chf].each do |currency_code|
        it "correctly handles #{currency_code.upcase}" do
          subscription.update!(billing_currency: currency_code)
          currency = subject.send(:resolve_account_currency, subscription)
          expect(currency).to eq(currency_code.upcase)
        end
      end
    end
  end

  describe "#get_or_create_account" do
    subject { described_class.new }

    before do
      allow(account_class).to receive(:find_by_external_key).and_raise(
        KillBill::Client::API::NotFound.new("Account not found")
      )
    end

    context "when creating a new account" do
      let(:new_account) do
        double(
          "KillBill::Client::Model::Account",
          account_id: "new-account-id",
          email: subscription.email,
          currency: "EUR"
        )
      end

      before do
        allow(account_class).to receive(:new).and_return(new_account)
        allow(new_account).to receive(:create).and_return(new_account)
        allow(new_account).to receive(:external_key=)
        allow(new_account).to receive(:name=)
        allow(new_account).to receive(:email=)
        allow(new_account).to receive(:currency=)
        allow(new_account).to receive(:bill_cycle_day_local=)
        allow(new_account).to receive(:time_zone=)
      end

      it "sets the currency based on subscription's billing_currency" do
        subscription.update!(billing_currency: "eur")

        expect(new_account).to receive(:currency=).with("EUR")

        subject.send(:get_or_create_account, subscription)
      end

      it "sets the currency to USD for legacy subscriptions" do
        subscription.update!(billing_currency: "usd")

        expect(new_account).to receive(:currency=).with("USD")

        subject.send(:get_or_create_account, subscription)
      end
    end
  end
end
