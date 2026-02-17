# frozen_string_literal: true

class BatchBillingWorker
  include Sidekiq::Job
  sidekiq_options retry: 0, queue: :default

  def perform
    today = Time.current.day

    Link.alive.is_recurring_billing.batch_billing_enabled.find_each do |link|
      next unless link.batch_billing_day.to_i == today

      process_product(link)
    end
  end

  private
    def process_product(link)
      link.subscriptions
        .not_is_test_subscription
        .where(deactivated_at: nil)
        .includes(:original_purchase, :last_successful_purchase, last_payment_option: :price)
        .find_each do |subscription|
          process_subscription(subscription, link)
        rescue => e
          Rails.logger.error("BatchBillingWorker: Error processing subscription #{subscription.id}: #{e.message}")
        end
    end

    def process_subscription(subscription, link)
      return if subscription.link.user.suspended?
      return unless subscription.alive?(include_pending_cancellation: false)
      return if subscription.current_subscription_price_cents == 0
      return if subscription.charges_completed?
      return if subscription.in_free_trial?
      return if subscription.has_a_charge_in_progress?

      last_successful = subscription.last_successful_purchase
      if last_successful.present?
        return if (last_successful.created_at + subscription.period) > Time.current
      else
        return unless subscription.overdue_for_charge?
      end

      Rails.logger.info("BatchBillingWorker: Charging subscription #{subscription.id} for product #{link.id}")
      purchase = subscription.charge!

      if purchase.successful? && link.batch_entitlement_enabled?
        subscription.grant_batch_entitlement!
      end
    end
end
