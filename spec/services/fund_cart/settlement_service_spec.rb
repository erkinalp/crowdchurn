# frozen_string_literal: true

describe FundCart::SettlementService do
  let(:buyer) { create(:user, :eligible_for_service_products, name: "Buyer Example", country: "United States", state: "OR", zip_code: "97201", street_address: "123 Main St", city: "Portland") }
  let(:cart) { create(:fund_cart_product, user: buyer).fund_cart }
  let(:product) { create(:product, price_cents: 1000) }
  let!(:item) { create(:fund_cart_item, fund_cart: cart, product:) }

  def reserve
    quote = FundCart::QuoteService.new(item: item.reload).perform
    FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
  end

  it "atomically consumes backing, credits the actual seller once, and creates a verifiable receipt" do
    lot = back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    expect(cart.available_subunits).to eq(1000)
    expect(cart.reserved_subunits).to eq(1000)
    expect(settlement.purchase.funded_by_fund_cart?).to eq(false)
    expect(settlement.purchase.balance_transactions).to be_empty

    2.times { described_class.new(settlement:).perform }
    purchase = settlement.purchase.reload
    expect(item.reload.state).to eq("purchased")
    expect(purchase.funded_by_fund_cart?).to eq(true)
    expect(purchase.stripe_transaction_id).to be_nil
    expect(purchase.charge).to be_nil
    expect(purchase.charge_processor_id).to be_nil
    expect(purchase.balance_transactions.count).to eq(1)
    expect(purchase.purchase_success_balance.user_id).to eq(product.user_id)
    expect(purchase.purchase_success_balance.amount_cents).to eq(purchase.payment_cents)
    expect(lot.reload.spent_subunits).to eq(1000)
    expect(cart.reserved_subunits).to eq(0)
    expect(cart.ledger_entries.sum(:amount_subunits)).to eq(0)
    expect(settlement.operations.where(kind: "fulfill").count).to eq(1)

    expect { purchase.increment_sellers_balance! }.not_to change { purchase.balance_transactions.count }
    purchase.total_transaction_cents += 1
    expect(purchase.funded_by_fund_cart?).to eq(false)
  end

  it "requires receipt-linked accounting and rejects tampered purchase snapshots" do
    back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    described_class.new(settlement:).perform
    purchase = settlement.purchase.reload
    expect(purchase).to be_funded_by_fund_cart
    purchase.price_cents += 1
    expect(purchase).not_to be_funded_by_fund_cart
    purchase.reload
    purchase.seller_id = buyer.id
    expect(purchase).not_to be_funded_by_fund_cart
    purchase.reload
    purchase.merchant_account_id += 1
    expect(purchase).not_to be_funded_by_fund_cart
    purchase.reload
    settlement.update!(receipt: settlement.receipt.merge("seller_balance_transaction_id" => 0))
    expect(purchase).not_to be_funded_by_fund_cart
  end

  it "keeps historical receipts valid after a destination is repriced" do
    back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    described_class.new(settlement:).perform
    product.update!(price_cents: 2000)
    expect(settlement.purchase.reload).to be_funded_by_fund_cart
  end

  it "rejects capped inventory until a durable inventory reservation route exists" do
    cart.activate_ledger!
    product.update!(max_purchase_count: 1)
    expect(FundCart::Eligibility.destination(fund_cart: cart, product:).code).to eq("inventory_reservation_unverified")
  end

  it "does not treat a reversed spent amount as reusable credit or erase its deficit" do
    lot = back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    described_class.new(settlement:).perform
    lot.reload.update!(reversed_subunits: 1000, debt_subunits: 1000)
    expect(lot).to be_valid
    expect(lot).not_to be_spendable
    expect(cart.debt_subunits).to eq(1000)
    expect(cart.available_subunits).to eq(0)
    expect(FundCart::Eligibility.destination(fund_cart: cart, product:).code).to eq("cart_debt_requires_reconciliation")
    lot.debt_subunits = 0
    expect(lot).not_to be_valid
  end

  it "runs ordinary fulfillment through the durable operation after monetary finalization" do
    back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    described_class.new(settlement:).perform
    operation = settlement.operations.find_by!(kind: "fulfill")
    FundCartOperationJob.new.perform(operation.id)
    expect(operation.reload.state).to eq("completed")
    expect(settlement.purchase.reload).to be_successful
    expect(settlement.reload.fulfilled_at).to be_present
    expect { FundCartOperationJob.new.perform(operation.id) }.not_to change { settlement.purchase.balance_transactions.count }
  end

  it "does not authorize success with a boolean or an unsettled reservation" do
    back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    purchase = settlement.purchase
    purchase.skip_preparing_for_charge = true
    purchase.fund_cart_pricing = true
    purchase.purchase_state = "successful"
    expect(purchase).not_to be_valid
    expect(purchase.errors[:base]).to include("Fund cart settlement receipt is invalid.")
  end

  it "does not let a cached missing settlement bypass payout exclusion or charge a card" do
    back_fund_cart(cart, net_subunits: 2000)
    quote = FundCart::QuoteService.new(item:).perform
    purchase = quote.purchase
    expect(purchase.fund_cart_settlement).to be_nil
    FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
    expect { purchase.increment_sellers_balance! }.to raise_error(FundCart::SettlementError, "invalid_settlement_receipt")
    purchase.chargeable = Object.new
    expect { purchase.charge! }.to raise_error(FundCart::SettlementError, "funded_destination_cannot_charge")
    expect(purchase.balance_transactions).to be_empty
  end

  it "does not allow a second reservation for the same item" do
    back_fund_cart(cart, net_subunits: 3000)
    quote = FundCart::QuoteService.new(item:).perform
    service = FundCart::AllocateFundsService.new(fund_cart: cart)
    first = service.reserve!(item:, quote:)
    second = service.reserve!(item: item.reload, quote:)
    expect(second).to be_nil
    expect(cart.settlements.pluck(:id)).to eq([first.id])
    expect(cart.reserved_subunits).to eq(1000)
  end

  it "releases an unexecuted reservation exactly once without deleting its history" do
    lot = back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    expect { item.mark_removed! }.to raise_error(FundCart::SettlementError, "item_has_active_settlement")
    2.times { FundCart::CancelSettlementService.perform(settlement:, operation_key: "cancel:#{settlement.id}") }
    expect(settlement.reload.state).to eq("cancelled")
    expect(lot.reload.available_subunits).to eq(2000)
    expect(lot.reserved_subunits).to eq(0)
    expect(item.reload.removal_blocking_reason).to be_nil
    expect(settlement.allocations.first.state).to eq("cancelled")
    expect(settlement.purchase.balance_transactions).to be_empty
    expect(cart.ledger_entries.sum(:amount_subunits)).to eq(0)
  end

  it "keeps a changed quote reserved for reconciliation and does not credit a seller" do
    back_fund_cart(cart, net_subunits: 2000)
    settlement = reserve
    product.update!(price_cents: 2000)
    expect { described_class.new(settlement:).perform }.to raise_error(FundCart::SettlementError, "quote_changed")
    expect(settlement.reload.state).to eq("reconciling")
    expect(cart.reserved_subunits).to eq(1000)
    expect(item.reload.state).to eq("pending")
    expect(settlement.purchase.balance_transactions).to be_empty
  end

  it "never spends a legacy scalar balance or a pending provider credit" do
    cart.update!(balance_subunits: 5000)
    FundCart::AllocateFundsService.new(fund_cart: cart).perform
    expect(item.reload.state).to eq("pending")
    cart.update!(balance_subunits: 0)
    restrict_fund_cart_contribution(cart, net_subunits: 2000)
    FundCart::AllocateFundsService.new(fund_cart: cart).perform
    expect(item.reload.state).to eq("pending")
    expect(cart.settlements).to be_empty
    expect(cart.available_subunits).to eq(0)
  end

  it "quotes complete variant, quantity and shipping prices rather than the product list price" do
    product.update!(is_physical: true, require_shipping: true, native_type: "physical")
    product.shipping_destinations << create(:shipping_destination, country_code: "US", one_item_rate_cents: 300, multiple_items_rate_cents: 200)
    variant = create(:variant, variant_category: create(:variant_category, link: product), price_difference_cents: 500)
    item.update!(purchase_options: { "variant_ids" => [variant.id], "quantity" => 2 })
    back_fund_cart(cart, net_subunits: 10000)
    quote = FundCart::QuoteService.new(item: item.reload).perform
    expect(quote.purchase.displayed_price_cents).to eq(3000)
    expect(quote.purchase.shipping_cents).to eq(500)
    expect(quote.purchase.total_transaction_cents).to eq(3500)
    settlement = FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
    described_class.new(settlement:).perform
    expect(settlement.amount_subunits).to eq(3500)
    expect(cart.available_subunits).to eq(6500)
  end

  it "includes applicable platform sales tax in the amount reserved" do
    buyer.update!(country: "United Kingdom", state: nil, zip_code: "SW1A 1AA")
    create(:zip_tax_rate, country: "GB", combined_rate: 0.2, is_seller_responsible: false)
    back_fund_cart(cart, net_subunits: 2000)
    quote = FundCart::QuoteService.new(item:).perform
    expect(quote.purchase.gumroad_tax_cents).to be > 0
    expect(quote.snapshot["amount_subunits"]).to eq(quote.purchase.price_cents + quote.purchase.gumroad_tax_cents)
    settlement = FundCart::AllocateFundsService.new(fund_cart: cart).reserve!(item:, quote:)
    expect(settlement.amount_subunits).to eq(quote.purchase.total_transaction_cents)
  end
end
