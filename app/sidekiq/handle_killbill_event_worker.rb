# frozen_string_literal: true

class HandleKillbillEventWorker
  include Sidekiq::Job
  sidekiq_options queue: :default, retry: 3

  SUBSCRIPTION_EVENT_TYPES = %w[
    SUBSCRIPTION_CREATION
    SUBSCRIPTION_PHASE
    SUBSCRIPTION_CHANGE
    SUBSCRIPTION_CANCEL
    SUBSCRIPTION_UNCANCEL
    SUBSCRIPTION_BCD_CHANGE
  ].freeze

  INVOICE_EVENT_TYPES = %w[
    INVOICE_CREATION
    INVOICE_ADJUSTMENT
    INVOICE_NOTIFICATION
    INVOICE_PAYMENT_SUCCESS
    INVOICE_PAYMENT_FAILED
  ].freeze

  PAYMENT_EVENT_TYPES = %w[
    PAYMENT_SUCCESS
    PAYMENT_FAILED
    PAYMENT_REFUND
    PAYMENT_CHARGEBACK
  ].freeze

  def perform(killbill_event)
    event_type = killbill_event["eventType"]

    if SUBSCRIPTION_EVENT_TYPES.include?(event_type)
      handle_subscription_event(killbill_event)
    elsif INVOICE_EVENT_TYPES.include?(event_type)
      handle_invoice_event(killbill_event)
    elsif PAYMENT_EVENT_TYPES.include?(event_type)
      KillbillChargeProcessor.handle_killbill_event(killbill_event)
    else
      Rails.logger.info("HandleKillbillEventWorker: Unhandled event type: #{event_type}")
    end
  end

  private
    def handle_subscription_event(killbill_event)
      event_type = killbill_event["eventType"]
      subscription_id = killbill_event["objectId"]
      external_key = killbill_event["externalKey"]

      subscription = find_subscription(external_key || subscription_id)
      return unless subscription

      merchant_account = subscription.link&.user&.merchant_accounts&.killbill&.first
      return unless merchant_account

      case event_type
      when "SUBSCRIPTION_CREATION"
        handle_subscription_creation(subscription, killbill_event)
      when "SUBSCRIPTION_CANCEL"
        handle_subscription_cancellation(subscription, killbill_event)
      when "SUBSCRIPTION_UNCANCEL"
        handle_subscription_reactivation(subscription, killbill_event)
      when "SUBSCRIPTION_CHANGE"
        handle_subscription_change(subscription, killbill_event)
      when "SUBSCRIPTION_PHASE"
        handle_subscription_phase_change(subscription, killbill_event)
      end
    end

    def handle_invoice_event(killbill_event)
      event_type = killbill_event["eventType"]
      invoice_id = killbill_event["objectId"]
      account_id = killbill_event["accountId"]

      subscription = find_subscription_by_account(account_id)
      return unless subscription

      merchant_account = subscription.link&.user&.merchant_accounts&.killbill&.first
      return unless merchant_account

      invoice_handler = KillbillInvoiceHandler.new(merchant_account)

      case event_type
      when "INVOICE_CREATION"
        Rails.logger.info("HandleKillbillEventWorker: Invoice created: #{invoice_id}")
      when "INVOICE_PAYMENT_SUCCESS"
        invoice_handler.process_invoice_notification(invoice_id)
      when "INVOICE_PAYMENT_FAILED"
        handle_invoice_payment_failed(subscription, invoice_id, merchant_account)
      end
    end

    def handle_subscription_creation(subscription, _killbill_event)
      Rails.logger.info("HandleKillbillEventWorker: Subscription created in Kill Bill: #{subscription.external_id}")
    end

    def handle_subscription_cancellation(subscription, killbill_event)
      return if subscription.cancelled_at.present?

      effective_date = killbill_event["effectiveDate"]
      cancel_immediately = effective_date.present? && Time.parse(effective_date) <= Time.current

      if cancel_immediately
        subscription.cancel_effective_immediately!
      else
        subscription.cancel!(by_seller: true)
      end

      Rails.logger.info("HandleKillbillEventWorker: Subscription cancelled: #{subscription.external_id}")
    end

    def handle_subscription_reactivation(subscription, _killbill_event)
      return unless subscription.cancelled_at.present? || subscription.failed_at.present?

      subscription.resubscribe!
      subscription.send_restart_notifications!(Subscription::ResubscriptionReason::PAYMENT_ISSUE_RESOLVED)

      Rails.logger.info("HandleKillbillEventWorker: Subscription reactivated: #{subscription.external_id}")
    end

    def handle_subscription_change(subscription, killbill_event)
      new_plan = killbill_event["newPlan"]
      return unless new_plan.present?

      Rails.logger.info("HandleKillbillEventWorker: Subscription plan changed to #{new_plan}: #{subscription.external_id}")
    end

    def handle_subscription_phase_change(subscription, killbill_event)
      new_phase = killbill_event["newPhase"]

      if new_phase == "EVERGREEN" && subscription.in_free_trial?
        Rails.logger.info("HandleKillbillEventWorker: Free trial ended for subscription: #{subscription.external_id}")
      end
    end

    def handle_invoice_payment_failed(subscription, invoice_id, merchant_account)
      return unless subscription.alive?

      CustomerLowPriorityMailer.subscription_card_declined(subscription.id).deliver_later(queue: "low")
      ChargeDeclinedReminderWorker.perform_in(
        Subscription::ALLOWED_TIME_BEFORE_FAIL_AND_UNSUBSCRIBE - Subscription::CHARGE_DECLINED_REMINDER_EMAIL,
        subscription.id
      )
      UnsubscribeAndFailWorker.perform_in(
        Subscription::ALLOWED_TIME_BEFORE_FAIL_AND_UNSUBSCRIBE,
        subscription.id
      )

      Rails.logger.info("HandleKillbillEventWorker: Invoice payment failed for subscription: #{subscription.external_id}, invoice: #{invoice_id}")
    end

    def find_subscription(identifier)
      Subscription.find_by(external_id: identifier) ||
        Subscription.joins(:purchases).where(purchases: { stripe_transaction_id: identifier }).first
    end

    def find_subscription_by_account(account_id)
      return nil unless account_id.present?

      external_key_match = account_id.match(/crowdchurn_(.+)/)
      return nil unless external_key_match

      user_external_id = external_key_match[1]
      user = User.find_by(external_id: user_external_id)
      return nil unless user

      user.subscriptions.alive.first
    end
end
