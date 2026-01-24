# frozen_string_literal: true

require "spec_helper"

describe KillbillCatalogManager do
  include CurrencyHelper

  let(:seller) { create(:user) }

  describe "#currencies_for_product" do
    subject { described_class.new }

    context "with legacy pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_currency_type: "usd", pricing_mode: :legacy) }

      it "returns only the product's default currency" do
        currencies = subject.send(:currencies_for_product, product)
        expect(currencies).to eq(["USD"])
      end
    end

    context "with gross pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_currency_type: "usd", pricing_mode: :gross) }

      it "returns all supported catalog currencies" do
        currencies = subject.send(:currencies_for_product, product)
        expect(currencies).to eq(KillbillCatalogManager::SUPPORTED_CATALOG_CURRENCIES)
      end
    end

    context "with multi_currency pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_currency_type: "usd", pricing_mode: :multi_currency) }

      before do
        create(:price, link: product, price_cents: 900, currency: "eur", recurrence: "monthly")
        create(:price, link: product, price_cents: 800, currency: "gbp", recurrence: "monthly")
      end

      it "returns currencies with explicit prices plus the default currency" do
        currencies = subject.send(:currencies_for_product, product)
        expect(currencies).to include("USD", "EUR", "GBP")
        expect(currencies).not_to include("JPY", "AUD", "CAD", "CHF")
      end
    end

    context "with nil pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_currency_type: "eur") }

      before do
        product.update_column(:pricing_mode, nil)
      end

      it "falls back to legacy behavior with product's default currency" do
        currencies = subject.send(:currencies_for_product, product)
        expect(currencies).to eq(["EUR"])
      end
    end
  end

  describe "#build_recurring_prices_for_currencies" do
    subject { described_class.new }

    let(:price) { create(:price, link: product, price_cents: 1000, currency: "usd", recurrence: "monthly") }

    context "with legacy pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd", pricing_mode: :legacy) }

      it "returns the base price in the product's currency" do
        prices = subject.send(:build_recurring_prices_for_currencies, product, price, ["USD"])
        expect(prices).to eq([{ currency: "USD", value: 10.0 }])
      end
    end

    context "with gross pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd", pricing_mode: :gross) }

      it "returns FX-converted prices for all currencies" do
        prices = subject.send(:build_recurring_prices_for_currencies, product, price, ["USD", "EUR"])

        expect(prices.length).to eq(2)
        expect(prices.find { |p| p[:currency] == "USD" }[:value]).to eq(10.0)
        expect(prices.find { |p| p[:currency] == "EUR" }[:value]).to be_a(Numeric)
      end
    end

    context "with multi_currency pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd", pricing_mode: :multi_currency) }

      before do
        create(:price, link: product, price_cents: 900, currency: "eur", recurrence: "monthly")
      end

      it "uses explicit prices when available" do
        prices = subject.send(:build_recurring_prices_for_currencies, product, price, ["USD", "EUR"])

        expect(prices.find { |p| p[:currency] == "USD" }[:value]).to eq(10.0)
        expect(prices.find { |p| p[:currency] == "EUR" }[:value]).to eq(9.0)
      end

      it "falls back to base price when explicit price is not available" do
        prices = subject.send(:build_recurring_prices_for_currencies, product, price, ["USD", "GBP"])

        expect(prices.find { |p| p[:currency] == "USD" }[:value]).to eq(10.0)
        expect(prices.find { |p| p[:currency] == "GBP" }[:value]).to eq(10.0)
      end
    end

    context "with JPY (single-unit currency)" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "jpy", pricing_mode: :legacy) }
      let(:price) { create(:price, link: product, price_cents: 1000, currency: "jpy", recurrence: "monthly") }

      it "does not divide by 100 for single-unit currencies" do
        prices = subject.send(:build_recurring_prices_for_currencies, product, price, ["JPY"])
        expect(prices.find { |p| p[:currency] == "JPY" }[:value]).to eq(1000.0)
      end
    end
  end

  describe "#price_cents_to_decimal" do
    subject { described_class.new }

    it "converts cents to decimal for standard currencies" do
      expect(subject.send(:price_cents_to_decimal, 1000, "usd")).to eq(10.0)
      expect(subject.send(:price_cents_to_decimal, 999, "eur")).to eq(9.99)
    end

    it "returns the value as-is for single-unit currencies like JPY" do
      expect(subject.send(:price_cents_to_decimal, 1000, "jpy")).to eq(1000.0)
    end
  end

  describe "#generate_catalog_for_product" do
    subject { described_class.new }

    context "with multi-currency product" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd", pricing_mode: :gross) }

      before do
        create(:price, link: product, price_cents: 1000, currency: "usd", recurrence: "monthly")
      end

      it "generates a catalog with multiple currencies" do
        catalog_xml = subject.generate_catalog_for_product(product)

        expect(catalog_xml).to include("<currency>USD</currency>")
        expect(catalog_xml).to include("<currency>EUR</currency>")
        expect(catalog_xml).to include("<currency>GBP</currency>")
      end

      it "includes recurring prices for each currency" do
        catalog_xml = subject.generate_catalog_for_product(product)

        expect(catalog_xml).to include("<recurringPrice>")
        expect(catalog_xml).to include("<price>")
        expect(catalog_xml).to include("<value>")
      end
    end

    context "with legacy pricing mode" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd", pricing_mode: :legacy) }

      before do
        create(:price, link: product, price_cents: 1000, currency: "usd", recurrence: "monthly")
      end

      it "generates a catalog with only the product's default currency" do
        catalog_xml = subject.generate_catalog_for_product(product)

        expect(catalog_xml).to include("<currency>USD</currency>")
        expect(catalog_xml).not_to include("<currency>EUR</currency>")
      end
    end

    context "with free trial" do
      let(:product) { create(:subscription_product, user: seller, price_cents: 1000, price_currency_type: "usd", pricing_mode: :gross, free_trial_duration_in_days: 7) }

      before do
        create(:price, link: product, price_cents: 1000, currency: "usd", recurrence: "monthly")
      end

      it "includes trial phase with zero prices for all currencies" do
        catalog_xml = subject.generate_catalog_for_product(product)

        expect(catalog_xml).to include("TRIAL")
        expect(catalog_xml).to include("<fixedPrice>")
      end
    end
  end
end
