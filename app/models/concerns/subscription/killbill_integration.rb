# frozen_string_literal: true

module Subscription::KillbillIntegration
  extend ActiveSupport::Concern

  included do
    attr_accessor :killbill_subscription_id
  end

  def uses_killbill?
    merchant_account_for_subscription&.is_a_killbill_merchant_account?
  end

  def killbill_subscription_manager
    return nil unless uses_killbill?

    @killbill_subscription_manager ||= KillbillSubscriptionManager.new(merchant_account_for_subscription)
  end

  def killbill_catalog_manager
    return nil unless uses_killbill?

    @killbill_catalog_manager ||= KillbillCatalogManager.new(merchant_account_for_subscription)
  end

  def killbill_invoice_handler
    return nil unless uses_killbill?

    @killbill_invoice_handler ||= KillbillInvoiceHandler.new(merchant_account_for_subscription)
  end

  def create_killbill_subscription(payment_method_id: nil, plan_name: nil)
    return nil unless uses_killbill?

    killbill_subscription_manager.create_subscription(
      subscription: self,
      payment_method_id: payment_method_id,
      plan_name: plan_name
    )
  end

  def cancel_killbill_subscription(cancel_immediately: false)
    return nil unless uses_killbill?

    killbill_subscription_manager.cancel_subscription(
      external_id,
      cancel_immediately: cancel_immediately
    )
  end

  def pause_killbill_subscription
    return nil unless uses_killbill?

    killbill_subscription_manager.pause_subscription(external_id)
  end

  def resume_killbill_subscription
    return nil unless uses_killbill?

    killbill_subscription_manager.resume_subscription(external_id)
  end

  def change_killbill_plan(new_plan_name:, change_immediately: true)
    return nil unless uses_killbill?

    killbill_subscription_manager.change_plan(
      external_id,
      new_plan_name: new_plan_name,
      change_immediately: change_immediately
    )
  end

  def sync_with_killbill
    return nil unless uses_killbill?

    killbill_subscription_manager.sync_subscription_with_killbill(self)
  end

  def killbill_invoices
    return [] unless uses_killbill?

    killbill_subscription = killbill_subscription_manager.get_subscription(external_id)
    return [] unless killbill_subscription&.account_id

    killbill_subscription_manager.get_invoices(killbill_subscription.account_id)
  end

  def retry_killbill_payment(invoice_id: nil, payment_method_id: nil)
    return nil unless uses_killbill?

    if invoice_id.present?
      killbill_invoice_handler.retry_invoice_payment(invoice_id, payment_method_id: payment_method_id)
    else
      unpaid_invoices = killbill_invoices.reject(&:paid?)
      return nil if unpaid_invoices.empty?

      killbill_invoice_handler.retry_invoice_payment(
        unpaid_invoices.first.id,
        payment_method_id: payment_method_id
      )
    end
  end

  private
    def merchant_account_for_subscription
      @merchant_account_for_subscription ||= begin
        seller_merchant_account = seller&.merchant_accounts&.killbill&.charge_processor_alive&.first
        seller_merchant_account || MerchantAccount.operator(KillbillChargeProcessor.charge_processor_id)
      end
    end
end
