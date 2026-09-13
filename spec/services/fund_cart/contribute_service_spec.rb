# frozen_string_literal: true

describe FundCart::ContributeService do
  let(:seller) { create(:user, :eligible_for_service_products) }
  let(:fund_cart_product) { create(:fund_cart_product, user: seller, price_cents: 0, customizable_price: true) }
  let(:fund_cart) { fund_cart_product.fund_cart }
  let!(:item) { create(:fund_cart_item, fund_cart:, product: create(:product, price_cents: 1000)) }

  it "restricts seller proceeds before any withdrawable seller balance exists" do
    lot = restrict_fund_cart_contribution(fund_cart, net_subunits: 3000)
    purchase = lot.source_purchase
    expect(purchase.purchase_success_balance_id).to be_nil
    expect(purchase.balance_transactions.where(user_id: seller.id)).to be_empty
    expect(fund_cart.available_subunits).to eq(0)
    expect(fund_cart.pending_subunits).to eq(3000)
    expect(lot.gross_subunits).to eq(3500)
    expect(lot.fee_subunits).to eq(500)
    expect(lot.net_subunits).to eq(3000)
    expect(lot.restricted_at).to be_present
  end

  it "confirms only net custody once and deduplicates repeated source callbacks" do
    lot = back_fund_cart(fund_cart, net_subunits: 3000)
    2.times do
      described_class.new(purchase: lot.source_purchase).perform
      described_class.confirm!(lot:)
    end
    expect(fund_cart.available_subunits).to eq(3000)
    expect(fund_cart.funding_lots.count).to eq(1)
    expect(fund_cart.settlement_operations.where(kind: "confirm_source").count).to eq(1)
    expect(lot.ledger_entries.count).to eq(2)
    expect(lot.ledger_entries.sum(:amount_subunits)).to eq(0)
  end

  it "does not recover spendable backing from a historical successful callback" do
    fund_cart.update!(ledger_state: "legacy", ledger_activated_at: nil, activation_evidence: nil)
    operator = MerchantAccount.operator(StripeChargeProcessor.charge_processor_id) || create(:merchant_account, user: nil)
    purchase = create(:purchase, link: fund_cart_product, price_cents: 5000, merchant_account: operator)
    described_class.new(purchase:).perform
    expect(fund_cart.funding_lots).to be_empty
    expect(fund_cart.available_subunits).to eq(0)
    expect { fund_cart.activate_ledger! }.to raise_error(FundCart::SettlementError, "historical_cart_requires_reconciliation")
  end

  it "keeps rejected custody evidence pending rather than increasing available funds" do
    lot = restrict_fund_cart_contribution(fund_cart, net_subunits: 3000)
    allow(FundCart::StripeCustody).to receive(:confirm).with(lot:).and_raise(FundCart::SettlementError, "source_capture_unconfirmed")
    expect { described_class.confirm!(lot:) }.to raise_error(FundCart::SettlementError, "source_capture_unconfirmed")
    expect(fund_cart.available_subunits).to eq(0)
    expect(lot.reload.state).to eq("pending")
    expect(lot.ledger_entries).to be_empty
  end

  it "rejects evidence for the wrong custody account" do
    lot = restrict_fund_cart_contribution(fund_cart, net_subunits: 3000)
    allow(FundCart::StripeCustody).to receive(:confirm).with(lot:).and_return("custody_key" => "other")
    expect { described_class.confirm!(lot:) }.to raise_error(FundCart::SettlementError, "source_evidence_mismatch")
    expect(fund_cart.available_subunits).to eq(0)
  end

  it "disables an independent merchant without redirecting it to an operator account" do
    create(:merchant_account, user: item.product.user, charge_processor_merchant_id: "acct_independent_fund_cart")
    fund_cart.activate_ledger!
    result = FundCart::Eligibility.destination(fund_cart:, product: item.product)
    expect(result).not_to be_supported
    expect(result.code).to eq("external_merchant_reservation_unverified")
  end

  it "disables cross-currency and crypto backing instead of applying a two-decimal conversion" do
    fund_cart.activate_ledger!
    expect(FundCart::Eligibility.currency_supported?("btc")).to eq(false)
    expect(FundCart::Eligibility.currency_supported?("eur")).to eq(false)
    item.product.price_currency_type = "jpy"
    expect(FundCart::Eligibility.destination(fund_cart:, product: item.product).code).to eq("currency_conversion_not_supported")
  end

  it "activates a newly created empty cart without importing any balances" do
    expect(fund_cart).to be_ledger_active
    expect(fund_cart.activation_evidence).to eq("kind" => "empty_cart")
    expect(fund_cart.available_subunits).to eq(0)
    expect(fund_cart.funding_lots).to be_empty
  end

  it "checks the final merchant and processor currency without restricting ordinary purchases" do
    operator = MerchantAccount.operator("stripe") || create(:merchant_account, user: nil)
    external = create(:merchant_account, user: seller, charge_processor_merchant_id: "acct_external_contribution")
    purchase = build(:purchase, link: fund_cart_product, price_cents: 1000, merchant_account: operator)
    expect { purchase.ensure_fund_cart_funding_eligible!(resolved_merchant: external) }
      .to raise_error(FundCart::SettlementError, "external_merchant_reservation_unverified")
    expect { purchase.ensure_fund_cart_funding_eligible!(resolved_merchant: operator, processor_currency: "eur") }
      .to raise_error(FundCart::SettlementError, "buyer_currency_funding_not_supported")

    ordinary = build(:purchase, link: item.product, merchant_account: external)
    expect { ordinary.ensure_fund_cart_funding_eligible!(resolved_merchant: external, processor_currency: "eur") }.not_to raise_error
  end

  it "rejects affiliate-backed contributions before charging" do
    operator = MerchantAccount.operator("stripe") || create(:merchant_account, user: nil)
    purchase = build(:purchase, link: fund_cart_product, price_cents: 1000, merchant_account: operator,
                                affiliate: create(:direct_affiliate, seller:))
    purchase.chargeable = instance_double(Chargeable)
    expect(ChargeProcessor).not_to receive(:create_payment_intent_or_charge!)
    expect { purchase.charge! }.to raise_error(FundCart::SettlementError, "affiliate_settlement_not_supported")
  end

  it "rechecks contribution eligibility before confirming an existing payment intent" do
    operator = MerchantAccount.operator(StripeChargeProcessor.charge_processor_id) || create(:merchant_account, user: nil)
    purchase = build(:purchase, link: fund_cart_product, price_cents: 1000, merchant_account: operator,
                                affiliate: create(:direct_affiliate, seller:))
    allow(purchase).to receive(:processor_payment_intent_id).and_return("pi_unconfirmed_contribution")
    expect(ChargeProcessor).not_to receive(:confirm_payment_intent!)
    expect(purchase.confirm_charge_intent!).to be_nil
    expect(purchase.errors.full_messages.join).to include("affiliate_settlement_not_supported")
  end
end
