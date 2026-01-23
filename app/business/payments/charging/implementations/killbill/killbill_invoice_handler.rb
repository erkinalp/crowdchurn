# frozen_string_literal: true

class KillbillInvoiceHandler
  include KillbillErrorHandler

  INVOICE_STATUS_COMMITTED = "COMMITTED"
  INVOICE_STATUS_DRAFT = "DRAFT"
  INVOICE_STATUS_VOID = "VOID"

  def initialize(merchant_account)
    @merchant_account = merchant_account
    configure_client
  end

  def process_invoice_notification(invoice_id)
    with_killbill_error_handler do
      invoice = KillBill::Client::Model::Invoice.find_by_id(
        invoice_id,
        true,
        killbill_options
      )

      return nil unless invoice

      killbill_invoice = KillbillInvoice.new(invoice)

      if killbill_invoice.committed? && !killbill_invoice.paid?
        process_unpaid_invoice(killbill_invoice)
      elsif killbill_invoice.paid?
        process_paid_invoice(killbill_invoice)
      end

      killbill_invoice
    end
  end

  def create_invoice_for_subscription(subscription_id, target_date: nil)
    with_killbill_error_handler do
      subscription = KillBill::Client::Model::Subscription.find_by_external_key(
        subscription_id,
        killbill_options
      )

      return nil unless subscription

      invoice = KillBill::Client::Model::Invoice.trigger_invoice(
        subscription.account_id,
        target_date || Time.current.to_date.iso8601,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      KillbillInvoice.new(invoice) if invoice
    end
  end

  def void_invoice(invoice_id)
    with_killbill_error_handler do
      invoice = KillBill::Client::Model::Invoice.find_by_id(
        invoice_id,
        false,
        killbill_options
      )

      return nil unless invoice

      invoice.void(
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      KillbillInvoice.new(invoice)
    end
  end

  def add_credit_to_invoice(invoice_id, amount_cents, description: nil)
    with_killbill_error_handler do
      invoice = KillBill::Client::Model::Invoice.find_by_id(
        invoice_id,
        false,
        killbill_options
      )

      return nil unless invoice

      credit = KillBill::Client::Model::Credit.new
      credit.invoice_id = invoice_id
      credit.account_id = invoice.account_id
      credit.credit_amount = amount_cents / 100.0
      credit.description = description || "Credit applied via CrowdChurn"

      created_credit = credit.create(
        true,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      created_credit
    end
  end

  def get_invoice_payments(invoice_id)
    with_killbill_error_handler do
      payments = KillBill::Client::Model::InvoicePayment.find_all_by_invoice_id(
        invoice_id,
        true,
        killbill_options
      )

      payments.map { |payment| KillbillPayment.new(payment) }
    end
  end

  def retry_invoice_payment(invoice_id, payment_method_id: nil)
    with_killbill_error_handler do
      invoice = KillBill::Client::Model::Invoice.find_by_id(
        invoice_id,
        false,
        killbill_options
      )

      return nil unless invoice
      return nil if invoice.balance.to_f <= 0

      payment = invoice.pay(
        true,
        payment_method_id,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      KillbillPayment.new(payment) if payment
    end
  end

  def sync_invoice_with_purchase(invoice, subscription)
    return unless invoice.committed? && invoice.paid?

    purchase = find_or_create_purchase_for_invoice(invoice, subscription)
    return unless purchase

    if purchase.in_progress?
      purchase.update_balance_and_mark_successful!
      subscription.handle_purchase_success(purchase)
    end

    purchase
  end

  private
    def configure_client
      instance_url = @merchant_account&.killbill_instance_url.presence ||
                     ENV.fetch("KILLBILL_URL", nil)

      unless instance_url.present?
        raise ChargeProcessorInvalidRequestError.new(
          "Kill Bill instance URL not configured"
        )
      end

      KillBill::Client.url = instance_url
    end

    def killbill_options
      @killbill_options ||= {
        username: @merchant_account&.killbill_username.presence ||
                  ENV.fetch("KILLBILL_USER", nil),
        password: @merchant_account&.killbill_password.presence ||
                  ENV.fetch("KILLBILL_PASSWORD", nil),
        api_key: @merchant_account&.killbill_api_key.presence ||
                 ENV.fetch("KILLBILL_API_KEY", nil),
        api_secret: @merchant_account&.killbill_api_secret.presence ||
                    ENV.fetch("KILLBILL_API_SECRET", nil),
        reason: "CrowdChurn invoice handling",
        comment: "Automated via CrowdChurn"
      }
    end

    def process_unpaid_invoice(invoice)
      Rails.logger.info("KillbillInvoiceHandler: Processing unpaid invoice #{invoice.id}")

      subscription = find_subscription_for_invoice(invoice)
      return unless subscription

      if subscription.alive?
        CustomerLowPriorityMailer.subscription_card_declined(subscription.id).deliver_later(queue: "low")
      end
    end

    def process_paid_invoice(invoice)
      Rails.logger.info("KillbillInvoiceHandler: Processing paid invoice #{invoice.id}")

      subscription = find_subscription_for_invoice(invoice)
      return unless subscription

      sync_invoice_with_purchase(invoice, subscription)
    end

    def find_subscription_for_invoice(invoice)
      return nil unless invoice.line_items.present?

      subscription_item = invoice.line_items.find { |item| item.subscription_id.present? }
      return nil unless subscription_item

      Subscription.find_by(external_id: subscription_item.subscription_id) ||
        find_subscription_by_killbill_subscription_id(subscription_item.subscription_id)
    end

    def find_subscription_by_killbill_subscription_id(killbill_subscription_id)
      killbill_subscription = KillBill::Client::Model::Subscription.find_by_id(
        killbill_subscription_id,
        killbill_options
      )

      return nil unless killbill_subscription&.external_key

      Subscription.find_by(external_id: killbill_subscription.external_key)
    rescue StandardError => e
      Rails.logger.error("KillbillInvoiceHandler: Error finding subscription: #{e.message}")
      nil
    end

    def find_or_create_purchase_for_invoice(invoice, subscription)
      existing_purchase = subscription.purchases.find_by(
        stripe_transaction_id: invoice.id
      )

      return existing_purchase if existing_purchase

      purchase = subscription.build_purchase
      purchase.stripe_transaction_id = invoice.id
      purchase.charge_processor_id = KillbillChargeProcessor.charge_processor_id
      purchase.price_cents = invoice.amount_cents
      purchase.save!

      purchase
    rescue StandardError => e
      Rails.logger.error("KillbillInvoiceHandler: Error creating purchase for invoice: #{e.message}")
      nil
    end
end
