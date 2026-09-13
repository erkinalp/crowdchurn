# frozen_string_literal: true

class FundCart::CancelSettlementService
  def self.perform(settlement:, operation_key:)
    cart = settlement.fund_cart
    cart.with_lock do
      settlement.fund_cart_item.lock!
      settlement.lock!
      return settlement if settlement.state == "cancelled"
      unless settlement.state == "reserved"
        settlement.update!(cancel_requested_at: Time.current)
        raise FundCart::SettlementError, "settlement_requires_reconciliation"
      end
      operation = settlement.operations.create!(fund_cart: cart, operation_key:, kind: "ledger", state: "processing")
      postings = settlement.allocations.order(:fund_cart_funding_lot_id).flat_map do |allocation|
        lot = allocation.funding_lot
        lot.lock!
        raise FundCart::SettlementError, "allocation_not_reserved" unless allocation.state == "reserved"
        lot.update!(reserved_subunits: lot.reserved_subunits - allocation.amount_subunits, available_subunits: lot.available_subunits + allocation.amount_subunits)
        allocation.update!(state: "cancelled")
        dimensions = { currency: lot.currency, currency_exponent: lot.currency_exponent, fund_cart_settlement_id: settlement.id,
                       fund_cart_funding_lot_id: lot.id, user_id: lot.beneficiary_id, merchant_account_id: lot.source_merchant_account_id }
        [dimensions.merge(account: "reserved", amount_subunits: -allocation.amount_subunits),
         dimensions.merge(account: "available", amount_subunits: allocation.amount_subunits)]
      end
      FundCart::Ledger.post!(operation:, postings:)
      operation.update!(state: "completed", completed_at: Time.current)
      settlement.update!(state: "cancelled", active_item_id: nil)
      settlement.purchase.update!(purchase_state: "failed")
      settlement.fund_cart_item.update!(blocking_reason: nil)
      settlement.operations.where(kind: "settle", state: "pending").each { |work| work.update!(state: "cancelled") }
      cart.refresh_balance_projection!
    end
    settlement
  end
end
