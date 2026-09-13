# frozen_string_literal: true

describe FundCart::StripeCustody do
  let(:cart) { create(:fund_cart_product).fund_cart }
  let!(:item) { create(:fund_cart_item, fund_cart: cart) }
  let(:lot) { restrict_fund_cart_contribution(cart, net_subunits: 2000) }
  let(:payment_id) { lot.source_purchase.stripe_transaction_id }
  let(:result) { FundCart::Eligibility.account_result(lot.source_merchant_account) }
  let(:charge) do
    {
      id: payment_id, status: "succeeded", paid: true, captured: true, amount: 2500, amount_captured: 2500,
      currency: "usd", refunded: false, amount_refunded: 0, disputed: false,
      balance_transaction: { id: "txn_test", source: payment_id, currency: "usd", amount: 2500, fee: 200, net: 2300,
                             status: "available", available_on: 1.day.ago.to_i }
    }
  end

  def evidence
    described_class.evidence_for(lot:, charge:, payment_id:, result:)
  end

  it "retains native captured and canonical source amounts separately" do
    expect(evidence).to include("charge_gross_subunits" => 2500, "charge_net_subunits" => 2300, "source_net_subunits" => 2000,
                                "processor_fee_subunits" => 200, "currency_exponent" => 2, "custody_key" => lot.custody_key)
  end

  it "never calls a payment provider while a database transaction is open" do
    expect(Stripe::Charge).not_to receive(:retrieve)
    expect { described_class.confirm(lot:) }.to raise_error(FundCart::SettlementError, "external_request_inside_transaction")
  end

  it "rejects uncaptured authorizations" do
    charge[:captured] = false
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
  end

  it "rejects a transfer to another merchant even when the charge succeeded" do
    charge[:transfer] = "tr_external"
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
  end

  it "keeps provider-pending funds unavailable" do
    charge[:balance_transaction][:status] = "pending"
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_not_yet_available")
  end

  it "retains captured-but-pending evidence exclusively for reversal accounting" do
    charge[:amount_refunded] = 500
    charge[:balance_transaction][:status] = "pending"
    charge[:balance_transaction][:available_on] = 2.days.from_now.to_i
    reversal = described_class.evidence_for(lot:, charge:, payment_id:, result:, for_reversal: true)
    expect(reversal["availability_verified"]).to eq(false)
    expect(reversal["source_net_subunits"]).to eq(2000)
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
  end

  it "rejects partial refunds and disputes" do
    charge[:amount_refunded] = 1
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
    charge[:amount_refunded] = 0
    charge[:disputed] = true
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
  end

  it "rejects a provider balance transaction in another currency" do
    charge[:balance_transaction][:currency] = "eur"
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_balance_unconfirmed")
  end

  it "quarantines malformed balance amounts instead of repeatedly retrying them as pending" do
    charge[:balance_transaction][:fee] = nil
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_balance_unconfirmed")
    charge[:balance_transaction] = []
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
  end

  it "rejects a provider balance too small to cover the source obligations" do
    charge[:balance_transaction].merge!(net: 1900, fee: 600)
    expect { evidence }.to raise_error(FundCart::SettlementError, "source_net_insufficient")
  end
end
