# frozen_string_literal: true

class FundCartOutboxJob
  include Sidekiq::Job
  sidekiq_options queue: "low", retry: 3

  def perform
    FundCartSettlementOperation.due.find_each(&:dispatch)
    FundCartSettlementOperation.where(state: "processing").where("started_at < ?", 30.minutes.ago).find_each do |operation|
      operation.with_lock do
        next unless operation.state == "processing" && operation.started_at < 30.minutes.ago
        # A lost worker must not silently release a reservation or repeat an unknown fulfillment side effect.
        operation.update!(state: "reconciling", error_code: "worker_outcome_unknown")
      end
    end
    FundCartSettlementOperation.where(kind: FundCart::RefundService::REFUND_KINDS, state: "reconciling")
      .where("available_at IS NULL OR available_at <= ?", Time.current).find_each(&:dispatch)
  end
end
