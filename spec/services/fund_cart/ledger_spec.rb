# frozen_string_literal: true

describe FundCart::Ledger do
  let(:cart) { create(:fund_cart_product).fund_cart }
  let(:operation) { cart.settlement_operations.create!(operation_key: "ledger:test", kind: "ledger", state: "processing") }
  let(:postings) do
    [
      { account: "source_custody", currency: "usd", currency_exponent: 2, amount_subunits: -1000 },
      { account: "available", currency: "usd", currency_exponent: 2, amount_subunits: 1000 }
    ]
  end

  it "posts a balanced operation once and makes the entries immutable" do
    2.times { described_class.post!(operation:, postings:) }
    expect(operation.ledger_entries.count).to eq(2)
    expect(operation.ledger_entries.sum(:amount_subunits)).to eq(0)
    expect { operation.ledger_entries.first.update!(amount_subunits: 900) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { operation.ledger_entries.first.destroy! }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "rejects mismatched reuse of an operation key" do
    described_class.post!(operation:, postings:)
    changed = postings.map { |posting| posting.merge(amount_subunits: posting[:amount_subunits] * 2) }
    expect { described_class.post!(operation:, postings: changed) }.to raise_error(FundCart::SettlementError, "operation_key_reused")
    expect(operation.ledger_entries.count).to eq(2)
  end

  it "rejects unbalanced, cross-currency and fractional operations without partial writes" do
    expect { described_class.post!(operation:, postings: postings.first(1)) }.to raise_error(FundCart::SettlementError, "unbalanced_ledger_operation")
    postings.last[:currency] = "eur"
    expect { described_class.post!(operation:, postings:) }.to raise_error(FundCart::SettlementError, "unbalanced_ledger_operation")
    postings.last[:currency] = "usd"
    postings.each { |posting| posting[:amount_subunits] += 0.5 }
    expect { described_class.post!(operation:, postings:) }.to raise_error(FundCart::SettlementError, "fractional_base_units")
    expect(operation.ledger_entries).to be_empty
  end

  it "reverses with linked compensating entries rather than changing original history" do
    described_class.post!(operation:, postings:)
    operation.update!(state: "completed")
    reversal = cart.settlement_operations.create!(operation_key: "reverse:test", kind: "ledger", state: "processing")
    2.times { described_class.reverse!(operation: reversal, original_operation: operation) }
    expect(cart.ledger_entries.where(account: "available").sum(:amount_subunits)).to eq(0)
    expect(reversal.ledger_entries.pluck(:reversal_of_id)).to match_array(operation.ledger_entries.pluck(:id))
    duplicate = cart.settlement_operations.create!(operation_key: "reverse:duplicate", kind: "ledger", state: "processing")
    expect { described_class.reverse!(operation: duplicate, original_operation: operation) }.to raise_error(FundCart::SettlementError, "ledger_operation_already_reversed")
    expect(operation.ledger_entries.first.amount_subunits).to eq(-1000)
  end
end
