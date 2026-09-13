# frozen_string_literal: true

class FundCart::AllocateFundsService
  attr_reader :fund_cart

  def initialize(fund_cart:)
    @fund_cart = fund_cart
  end

  # Quote outside cart/lot locks. Reserve in one transaction, then execute the internal route after commit.
  def perform
    return unless fund_cart.ledger_active?
    fund_cart.pending_items.each do |item|
      next if item.active_settlement?
      quote = nil
      settlement = nil
      begin
        quote = FundCart::QuoteService.new(item:).perform
        settlement = reserve!(item:, quote:)
        FundCart::SettlementService.new(settlement:).perform if settlement
      rescue FundCart::SettlementError => error
        item.update!(blocking_reason: error.code.to_s.first(255)) unless item.reload.state == "purchased"
      ensure
        quote.purchase.update!(purchase_state: "failed") if quote && !settlement && quote.purchase.in_progress?
      end
    end
  end

  def reserve!(item:, quote:)
    fund_cart.with_lock do
      item.lock!
      return unless fund_cart.ledger_active? && item.state == "pending" && !item.active_settlement?
      raise FundCart::SettlementError, "quote_changed" unless FundCart::QuoteService.snapshot(quote.purchase, item:) == quote.snapshot
      eligible = FundCart::Eligibility.destination(fund_cart:, product: item.product).ensure_supported!
      raise FundCart::SettlementError, "custody_changed" unless eligible.custody_key == quote.eligibility.custody_key
      lots = fund_cart.funding_lots.where(state: "available", currency: fund_cart.currency, custody_key: eligible.custody_key).order(:id).lock.to_a.select(&:spendable?)
      amount = quote.purchase.total_transaction_cents
      raise FundCart::SettlementError, "insufficient_available_funds" if lots.sum(&:authorized_available_subunits) < amount
      settlement = fund_cart.settlements.create!(
        fund_cart_item: item, active_item_id: item.id, purchase: quote.purchase,
        beneficiary: fund_cart.user, seller: item.product.user, destination_merchant_account: eligible.merchant_account,
        custody_key: eligible.custody_key, route: eligible.route, currency: fund_cart.currency, currency_exponent: 2,
        operation_key: "fund-cart-item:#{item.id}:#{SecureRandom.uuid}", amount_subunits: amount, quote_snapshot: quote.snapshot
      )
      operation = settlement.operations.create!(fund_cart:, operation_key: "reserve:#{settlement.operation_key}", kind: "ledger", state: "processing")
      remaining = amount
      postings = []
      lots.each do |lot|
        used = [remaining, lot.authorized_available_subunits].min
        next if used.zero?
        settlement.allocations.create!(fund_cart_funding_lot: lot, amount_subunits: used, operation_key: "#{settlement.operation_key}:lot:#{lot.id}")
        dimensions = { currency: lot.currency, currency_exponent: lot.currency_exponent, fund_cart_funding_lot_id: lot.id, fund_cart_settlement_id: settlement.id,
                       user_id: lot.beneficiary_id, merchant_account_id: lot.source_merchant_account_id }
        postings << dimensions.merge(account: "available", amount_subunits: -used)
        postings << dimensions.merge(account: "reserved", amount_subunits: used)
        lot.update!(available_subunits: lot.available_subunits - used, reserved_subunits: lot.reserved_subunits + used)
        remaining -= used
        break if remaining.zero?
      end
      FundCart::Ledger.post!(operation:, postings:)
      operation.update!(state: "completed", completed_at: Time.current)
      item.update!(blocking_reason: "settlement_reserved")
      fund_cart.refresh_balance_projection!
      settlement.operations.create!(fund_cart:, operation_key: "execute:#{settlement.operation_key}", kind: "settle")
      settlement
    end
  end
end
