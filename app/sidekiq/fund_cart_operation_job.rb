# frozen_string_literal: true

class FundCartOperationJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 10

  def perform(operation_id)
    operation = FundCartSettlementOperation.find(operation_id)
    return FundCartRefundJob.new.perform(operation_id) if operation.kind.in?(FundCart::RefundService::REFUND_KINDS)
    claimed = operation.with_lock do
      next false unless operation.state == "pending"
      next false if operation.available_at && operation.available_at > Time.current
      operation.update!(state: "processing", started_at: Time.current, attempts: operation.attempts + 1)
      true
    end
    return unless claimed

    case operation.kind
    when "confirm_source"
      FundCart::ContributeService.confirm!(lot: operation.fund_cart_funding_lot)
    when "allocate"
      FundCart::AllocateFundsService.new(fund_cart: operation.fund_cart).perform
    when "settle"
      FundCart::SettlementService.new(settlement: operation.fund_cart_settlement).perform
    when "source_dispute"
      FundCart::RefundService.new(purchase: operation.purchase).resume_dispute!(operation)
    when "fulfill"
      fulfill(operation)
    else
      raise FundCart::SettlementError, "unsupported_operation_kind"
    end
    operation.update!(state: "completed", completed_at: Time.current, last_error: nil, error_code: nil)
  rescue FundCart::SettlementError => error
    waiting = error.code.in?(%w[source_not_yet_available source_reversal_pending])
    operation.update!(state: waiting ? "pending" : "reconciling", available_at: waiting ? 5.minutes.from_now : nil,
                      error_code: error.code, last_error: error.message)
    operation.fund_cart_funding_lot&.update!(blocking_reason: error.code) if operation.kind == "confirm_source"
    self.class.perform_in(5.minutes, operation.id) if waiting
  rescue StandardError => error
    operation&.update!(state: operation.kind.in?(%w[confirm_source source_dispute]) ? "pending" : "reconciling",
                       last_error: "#{error.class}: #{error.message}")
    raise
  end

  private
    def fulfill(operation)
      settlement = operation.fund_cart_settlement
      purchase = settlement.purchase
      raise FundCart::SettlementError, "invalid_settlement_receipt" unless purchase.funded_by_fund_cart?
      # Keep the ordinary successful-purchase callbacks, but run them only after money/item commit and without cart/lot locks.
      purchase.with_lock { purchase.update_balance_and_mark_successful! unless purchase.successful? }
      settlement.update!(fulfilled_at: Time.current)
    end
end
