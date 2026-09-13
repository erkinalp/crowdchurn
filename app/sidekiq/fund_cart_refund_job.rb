# frozen_string_literal: true

class FundCartRefundJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 10

  def perform(operation_id)
    operation = FundCartSettlementOperation.find(operation_id)
    reconcile = false
    claimed = operation.with_lock do
      next false unless operation.state.in?(%w[pending reconciling]) && operation.kind.in?(FundCart::RefundService::REFUND_KINDS)
      next false if operation.available_at && operation.available_at > Time.current
      reconcile = operation.state == "reconciling"
      operation.update!(state: "processing", started_at: Time.current, attempts: operation.attempts + 1)
      true
    end
    return unless claimed
    service = FundCart::RefundService.new(purchase: operation.purchase)
    reconcile ? service.reconcile!(operation) : service.perform(operation)
    if operation.reload.state == "processing"
      operation.update!(state: "reconciling", error_code: "refund_completion_unconfirmed", available_at: 5.minutes.from_now)
    end
    operation.update!(available_at: 5.minutes.from_now) if operation.state == "reconciling"
  rescue FundCart::SettlementError => error
    operation&.update!(state: "reconciling", error_code: error.code, last_error: error.message,
                       available_at: 5.minutes.from_now) unless operation&.reload&.state == "completed"
  rescue StandardError => error
    # Even an apparently local failure may follow a successful provider request.
    # Only lookup/callback evidence can complete this identity; Sidekiq must not resubmit it.
    operation&.update!(state: "reconciling", error_code: "refund_outcome_unknown",
                       last_error: "#{error.class}: #{error.message}", available_at: 5.minutes.from_now) unless operation&.reload&.state == "completed"
    raise unless error.is_a?(Stripe::StripeError)
  end
end
