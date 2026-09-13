# frozen_string_literal: true

module FundCartItemRemoval
  extend ActiveSupport::Concern

  private
    def remove_fund_cart_item!(item)
      cancellation_error = nil
      @fund_cart.with_lock do
        item.lock!
        raise FundCart::SettlementError, "only_pending_items_can_be_removed" unless item.state == "pending"

        settlement = item.settlements.where.not(active_item_id: nil).first
        if settlement
          begin
            FundCart::CancelSettlementService.perform(settlement:, operation_key: "remove-item:#{settlement.operation_key}")
          rescue FundCart::SettlementError => error
            raise unless error.code == "settlement_requires_reconciliation"
            # The core joins this transaction: commit its cancellation request, never release the reservation.
            cancellation_error = error
          end
        end
        # Keep cancellation and removal under the allocator's cart/item lock order.
        item.mark_removed! unless cancellation_error
      end
      raise cancellation_error if cancellation_error
    end
end
