# frozen_string_literal: true

describe MoneyFormatter do
  describe "#format" do
    it "formats a registered currency absent from product pricing choices" do
      expect(CURRENCY_CHOICES).not_to have_key(:dkk)
      expect(MoneyFormatter.format(1250, :dkk)).to eq "12.50 kr."
      expect(MoneyFormatter.format(1200, "dkk", no_cents_if_whole: true)).to eq "12 kr."
    end

    it "omits the historical currency symbol only when requested" do
      expect(MoneyFormatter.format(1250, :dkk, symbol: false)).to eq "12.50"
      expect(MoneyFormatter.format(1250, :dkk, symbol: true)).to eq "12.50 kr."
    end

    it "soft-fails unknown currencies with the ISO code instead of relabeling them as USD" do
      expect(Rails.logger).to receive(:warn).with(/unknown currency :xyz/).at_least(:once)
      expect(MoneyFormatter.format(1250, :xyz)).to eq "12.50 XYZ"
      expect(MoneyFormatter.format(1250, :xyz, symbol: false)).to eq "12.50"
      expect(MoneyFormatter.format(1250, :xyz)).not_to include("$")
    end

    it "soft-fails blank currencies without raising" do
      expect(Rails.logger).to receive(:warn).with(/unknown currency/).at_least(:once)
      expect(MoneyFormatter.format(1250, nil)).to eq "12.50"
      expect(MoneyFormatter.format(1250, "")).to eq "12.50"
    end

    describe "usd" do
      it "returns the correct string" do
        expect(MoneyFormatter.format(400, :usd)).to eq "$4.00"
      end

      it "returns correctly when no symbol desired" do
        expect(MoneyFormatter.format(400, :usd, symbol: false)).to eq "4.00"
      end
    end

    describe "jpy" do
      it "returns the correct string" do
        expect(MoneyFormatter.format(400, :jpy)).to eq "¥400"
      end
    end

    describe "aud" do
      it "returns the correct currency symbol" do
        expect(MoneyFormatter.format(400, :aud)).to eq "A$4.00"
      end

      it "honors uppercase pricing-choice keys" do
        expect(MoneyFormatter.format(400, "AUD")).to eq "A$4.00"
      end
    end
  end

  describe "#symbol_for" do
    it "uses the pricing override before the registry" do
      expect(MoneyFormatter.symbol_for(:aud)).to eq "A$"
      expect(MoneyFormatter.symbol_for("AUD")).to eq "A$"
    end

    it "uses the registry symbol for historical currencies" do
      expect(MoneyFormatter.symbol_for(:dkk)).to eq "kr."
    end

    it "soft-fails unknown currencies with the ISO code instead of relabeling them as USD" do
      expect(Rails.logger).to receive(:warn).with(/unknown currency :xyz/)
      symbol = MoneyFormatter.symbol_for(:xyz)
      expect(symbol).to eq("XYZ")
      expect(symbol).not_to eq("$")
    end

    it "soft-fails blank currencies with an empty string" do
      expect(Rails.logger).to receive(:warn).with(/unknown currency/).twice
      expect(MoneyFormatter.symbol_for(nil)).to eq ""
      expect(MoneyFormatter.symbol_for("")).to eq ""
    end
  end

  describe "#format_crypto" do
    describe "btc" do
      it "formats Bitcoin amounts correctly" do
        # 1 BTC = 100,000,000 satoshis
        expect(MoneyFormatter.format_crypto(100_000_000, :btc)).to eq "₿1"
        expect(MoneyFormatter.format_crypto(50_000_000, :btc)).to eq "₿0.5"
        expect(MoneyFormatter.format_crypto(1_000_000, :btc)).to eq "₿0.01"
      end

      it "handles small amounts" do
        expect(MoneyFormatter.format_crypto(1, :btc)).to eq "₿0.00000001"
      end

      it "returns correctly when no symbol desired" do
        expect(MoneyFormatter.format_crypto(100_000_000, :btc, symbol: false)).to eq "1"
      end
    end

    describe "eth" do
      it "formats Ethereum amounts correctly" do
        # 1 ETH = 10^18 wei
        expect(MoneyFormatter.format_crypto(1_000_000_000_000_000_000, :eth)).to eq "Ξ1"
        expect(MoneyFormatter.format_crypto(500_000_000_000_000_000, :eth)).to eq "Ξ0.5"
      end
    end

    describe "usdt (stablecoin)" do
      it "formats USDT amounts with 2 decimals like fiat" do
        # 1 USDT = 1,000,000 (6 decimals)
        expect(MoneyFormatter.format_crypto(1_000_000, :usdt)).to eq "₮1"
        expect(MoneyFormatter.format_crypto(1_500_000, :usdt)).to eq "₮1.5"
        expect(MoneyFormatter.format_crypto(1_990_000, :usdt)).to eq "₮1.99"
      end
    end

    describe "sol" do
      it "formats Solana amounts correctly" do
        # 1 SOL = 1,000,000,000 lamports (9 decimals)
        expect(MoneyFormatter.format_crypto(1_000_000_000, :sol)).to eq "SOL1"
        expect(MoneyFormatter.format_crypto(500_000_000, :sol)).to eq "SOL0.5"
      end
    end
  end

  describe "#format_crypto_full_precision" do
    it "formats with full decimal precision" do
      expect(MoneyFormatter.format_crypto_full_precision(12_345_678, :btc)).to eq "₿0.12345678"
      expect(MoneyFormatter.format_crypto_full_precision(1_234_567_890_123_456_789, :eth)).to eq "Ξ1.234567890123456789"
    end
  end
end
