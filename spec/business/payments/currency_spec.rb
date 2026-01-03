# frozen_string_literal: true

require "spec_helper"

describe Currency do
  describe ".crypto?" do
    it "returns true for cryptocurrencies" do
      expect(Currency.crypto?("btc")).to be true
      expect(Currency.crypto?("eth")).to be true
      expect(Currency.crypto?("usdt")).to be true
      expect(Currency.crypto?("usdc")).to be true
      expect(Currency.crypto?("ltc")).to be true
      expect(Currency.crypto?("sol")).to be true
      expect(Currency.crypto?("doge")).to be true
    end

    it "returns false for fiat currencies" do
      expect(Currency.crypto?("usd")).to be false
      expect(Currency.crypto?("gbp")).to be false
      expect(Currency.crypto?("eur")).to be false
      expect(Currency.crypto?("jpy")).to be false
    end

    it "handles case insensitivity" do
      expect(Currency.crypto?("BTC")).to be true
      expect(Currency.crypto?("ETH")).to be true
      expect(Currency.crypto?("USD")).to be false
    end
  end

  describe ".stablecoin?" do
    it "returns true for stablecoins" do
      expect(Currency.stablecoin?("usdt")).to be true
      expect(Currency.stablecoin?("usdc")).to be true
      expect(Currency.stablecoin?("dai")).to be true
    end

    it "returns false for volatile cryptocurrencies" do
      expect(Currency.stablecoin?("btc")).to be false
      expect(Currency.stablecoin?("eth")).to be false
      expect(Currency.stablecoin?("ltc")).to be false
    end

    it "returns false for fiat currencies" do
      expect(Currency.stablecoin?("usd")).to be false
      expect(Currency.stablecoin?("eur")).to be false
    end
  end

  describe ".volatile?" do
    it "returns true for volatile cryptocurrencies" do
      expect(Currency.volatile?("btc")).to be true
      expect(Currency.volatile?("eth")).to be true
      expect(Currency.volatile?("ltc")).to be true
      expect(Currency.volatile?("sol")).to be true
    end

    it "returns false for stablecoins" do
      expect(Currency.volatile?("usdt")).to be false
      expect(Currency.volatile?("usdc")).to be false
      expect(Currency.volatile?("dai")).to be false
    end

    it "returns false for fiat currencies" do
      expect(Currency.volatile?("usd")).to be false
      expect(Currency.volatile?("eur")).to be false
    end
  end

  describe ".decimals_for" do
    it "returns correct decimals for cryptocurrencies" do
      expect(Currency.decimals_for("btc")).to eq 8
      expect(Currency.decimals_for("eth")).to eq 18
      expect(Currency.decimals_for("usdt")).to eq 6
      expect(Currency.decimals_for("usdc")).to eq 6
      expect(Currency.decimals_for("sol")).to eq 9
      expect(Currency.decimals_for("ada")).to eq 6
      expect(Currency.decimals_for("dot")).to eq 10
    end

    it "returns 2 for fiat currencies" do
      expect(Currency.decimals_for("usd")).to eq 2
      expect(Currency.decimals_for("eur")).to eq 2
    end
  end

  describe ".subunit_to_unit" do
    it "returns correct subunit_to_unit for cryptocurrencies" do
      expect(Currency.subunit_to_unit("btc")).to eq 100_000_000
      expect(Currency.subunit_to_unit("eth")).to eq 1_000_000_000_000_000_000
      expect(Currency.subunit_to_unit("usdt")).to eq 1_000_000
      expect(Currency.subunit_to_unit("sol")).to eq 1_000_000_000
    end

    it "returns 100 for standard fiat currencies" do
      expect(Currency.subunit_to_unit("usd")).to eq 100
      expect(Currency.subunit_to_unit("eur")).to eq 100
    end
  end

  describe ".display_decimals_for" do
    it "returns 2 for stablecoins" do
      expect(Currency.display_decimals_for("usdt")).to eq 2
      expect(Currency.display_decimals_for("usdc")).to eq 2
      expect(Currency.display_decimals_for("dai")).to eq 2
    end

    it "returns up to 8 for volatile crypto" do
      expect(Currency.display_decimals_for("btc")).to eq 8
      expect(Currency.display_decimals_for("eth")).to eq 8
      expect(Currency.display_decimals_for("ada")).to eq 6
    end

    it "returns 2 for fiat currencies" do
      expect(Currency.display_decimals_for("usd")).to eq 2
      expect(Currency.display_decimals_for("eur")).to eq 2
    end
  end

  describe ".crypto_payment_method?" do
    it "returns true for crypto payment methods" do
      expect(Currency.crypto_payment_method?("bitcoin")).to be true
      expect(Currency.crypto_payment_method?("ethereum")).to be true
      expect(Currency.crypto_payment_method?("crypto_wallet")).to be true
      expect(Currency.crypto_payment_method?("crypto_btc")).to be true
    end

    it "returns true for currency codes" do
      expect(Currency.crypto_payment_method?("btc")).to be true
      expect(Currency.crypto_payment_method?("eth")).to be true
    end

    it "returns false for non-crypto payment methods" do
      expect(Currency.crypto_payment_method?("card")).to be false
      expect(Currency.crypto_payment_method?("paypal")).to be false
      expect(Currency.crypto_payment_method?(nil)).to be false
      expect(Currency.crypto_payment_method?("")).to be false
    end
  end

  describe ".crypto_currency_from_payment_method" do
    it "extracts currency from crypto_ prefix" do
      expect(Currency.crypto_currency_from_payment_method("crypto_btc")).to eq "btc"
      expect(Currency.crypto_currency_from_payment_method("crypto_eth")).to eq "eth"
    end

    it "maps common names to currency codes" do
      expect(Currency.crypto_currency_from_payment_method("bitcoin")).to eq "btc"
      expect(Currency.crypto_currency_from_payment_method("ethereum")).to eq "eth"
      expect(Currency.crypto_currency_from_payment_method("litecoin")).to eq "ltc"
      expect(Currency.crypto_currency_from_payment_method("solana")).to eq "sol"
      expect(Currency.crypto_currency_from_payment_method("dogecoin")).to eq "doge"
    end

    it "returns currency code if already a valid crypto" do
      expect(Currency.crypto_currency_from_payment_method("btc")).to eq "btc"
      expect(Currency.crypto_currency_from_payment_method("eth")).to eq "eth"
    end

    it "returns nil for non-crypto payment methods" do
      expect(Currency.crypto_currency_from_payment_method("card")).to be_nil
      expect(Currency.crypto_currency_from_payment_method("paypal")).to be_nil
      expect(Currency.crypto_currency_from_payment_method(nil)).to be_nil
    end
  end

  describe ".crypto_purchase?" do
    it "returns true if product currency is crypto" do
      expect(Currency.crypto_purchase?("btc")).to be true
      expect(Currency.crypto_purchase?("eth")).to be true
    end

    it "returns true if payment method is crypto" do
      expect(Currency.crypto_purchase?("usd", "bitcoin")).to be true
      expect(Currency.crypto_purchase?("usd", "crypto_btc")).to be true
    end

    it "returns false for fiat currency and non-crypto payment" do
      expect(Currency.crypto_purchase?("usd")).to be false
      expect(Currency.crypto_purchase?("usd", "card")).to be false
    end
  end

  describe ".crypto_refund_amount" do
    it "calculates net refund amount (original minus fees)" do
      expect(Currency.crypto_refund_amount(1000, 50)).to eq 950
      expect(Currency.crypto_refund_amount(500, 25)).to eq 475
    end

    it "returns 0 if fee exceeds original amount" do
      expect(Currency.crypto_refund_amount(50, 100)).to eq 0
    end

    it "returns 0 for zero or negative original amounts" do
      expect(Currency.crypto_refund_amount(0, 10)).to eq 0
      expect(Currency.crypto_refund_amount(-100, 10)).to eq 0
    end
  end
end
