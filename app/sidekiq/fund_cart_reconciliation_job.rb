# frozen_string_literal: true

class FundCartReconciliationJob
  include Sidekiq::Job
  sidekiq_options queue: "low", retry: 3, lock: :until_executed

  # Never convert an audit retry into a payment, repair, import or activation.
  def perform(fund_cart_id)
    report = FundCart::ReconciliationService.new(fund_cart: FundCart.find(fund_cart_id)).dry_run
    Rails.logger.info({ event: "fund_cart_reconciliation", fund_cart_id:, fingerprint: report.fingerprint,
                        activatable: report.activatable?, blockers: report.blockers }.to_json)
    report.as_json
  end
end
