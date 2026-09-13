# frozen_string_literal: true

class FundCart::Ledger
  # Positive postings increase an account; negative postings decrease it. Each operation balances per currency/exponent.
  def self.post!(operation:, postings:)
    normalized = postings.map(&:symbolize_keys).reject { |posting| posting.fetch(:amount_subunits).zero? }
    raise FundCart::SettlementError, "empty_ledger_operation" if normalized.empty?
    normalized.each do |posting|
      amount = posting.fetch(:amount_subunits)
      raise FundCart::SettlementError, "fractional_base_units" unless amount == amount.to_i
    end
    normalized.group_by { |posting| posting.values_at(:currency, :currency_exponent) }.each_value do |group|
      raise FundCart::SettlementError, "unbalanced_ledger_operation" unless group.sum { |posting| posting.fetch(:amount_subunits) }.zero?
    end

    operation.with_lock do
      existing = operation.ledger_entries.order(:position)
      if existing.exists?
        expected = normalized.map { |posting| posting.stringify_keys.transform_values { |value| value.is_a?(Numeric) ? value.to_i : value } }
        raise FundCart::SettlementError, "operation_key_reused" unless existing.size == expected.size
        actual = existing.map.with_index { |entry, index| entry.attributes.slice(*expected[index].keys).transform_values { |value| value.is_a?(Numeric) ? value.to_i : value } }
        raise FundCart::SettlementError, "operation_key_reused" unless actual == expected
        return existing.to_a
      end
      raise FundCart::SettlementError, "completed_operation_is_immutable" if operation.state == "completed"
      normalized.each_with_index.map do |posting, index|
        operation.ledger_entries.create!(**posting, fund_cart: operation.fund_cart, position: index)
      end
    end
  end

  def self.reverse!(operation:, original_operation:)
    raise FundCart::SettlementError, "wrong_reversal_cart" unless operation.fund_cart_id == original_operation.fund_cart_id
    raise FundCart::SettlementError, "cannot_reverse_itself" if operation.id == original_operation.id
    original_operation.with_lock do
      originals = original_operation.ledger_entries.order(:position)
      if FundCartLedgerEntry.where(reversal_of_id: originals.select(:id)).where.not(fund_cart_settlement_operation_id: operation.id).exists?
        raise FundCart::SettlementError, "ledger_operation_already_reversed"
      end
      post!(operation:, postings: originals.map do |entry|
        entry.attributes.symbolize_keys.slice(:account, :currency, :currency_exponent, :fund_cart_funding_lot_id, :fund_cart_settlement_id, :user_id, :merchant_account_id)
          .merge(amount_subunits: -entry.amount_subunits, reversal_of_id: entry.id)
      end)
    end
  end
end
