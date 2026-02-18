# frozen_string_literal: true

class KillbillSubscriptionManager
  include KillbillErrorHandler

  SUBSCRIPTION_STATE_ACTIVE = "ACTIVE"
  SUBSCRIPTION_STATE_CANCELLED = "CANCELLED"
  SUBSCRIPTION_STATE_BLOCKED = "BLOCKED"
  SUBSCRIPTION_STATE_PENDING = "PENDING"

  BILLING_PERIOD_MONTHLY = "MONTHLY"
  BILLING_PERIOD_ANNUAL = "ANNUAL"
  BILLING_PERIOD_WEEKLY = "WEEKLY"
  BILLING_PERIOD_QUARTERLY = "QUARTERLY"

  def initialize(merchant_account)
    @merchant_account = merchant_account
    configure_client
  end

  def create_subscription(subscription:, payment_method_id:, plan_name: nil)
    with_killbill_error_handler do
      account_id = get_or_create_account(subscription)

      killbill_subscription = KillBill::Client::Model::Subscription.new
      killbill_subscription.account_id = account_id
      killbill_subscription.plan_name = plan_name || generate_plan_name(subscription)
      killbill_subscription.external_key = subscription.external_id

      created_subscription = killbill_subscription.create(
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        nil,
        false,
        killbill_options
      )

      KillbillSubscription.new(created_subscription)
    end
  end

  def get_subscription(subscription_id)
    with_killbill_error_handler do
      killbill_subscription = KillBill::Client::Model::Subscription.find_by_external_key(
        subscription_id,
        killbill_options
      )

      KillbillSubscription.new(killbill_subscription) if killbill_subscription
    end
  end

  def cancel_subscription(subscription_id, cancel_immediately: false)
    with_killbill_error_handler do
      killbill_subscription = KillBill::Client::Model::Subscription.find_by_external_key(
        subscription_id,
        killbill_options
      )

      return nil unless killbill_subscription

      policy = cancel_immediately ? "IMMEDIATE" : "END_OF_TERM"

      killbill_subscription.cancel(
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        nil,
        policy,
        nil,
        false,
        killbill_options
      )

      KillbillSubscription.new(killbill_subscription)
    end
  end

  def pause_subscription(subscription_id)
    with_killbill_error_handler do
      killbill_subscription = KillBill::Client::Model::Subscription.find_by_external_key(
        subscription_id,
        killbill_options
      )

      return nil unless killbill_subscription

      blocking_state = KillBill::Client::Model::BlockingState.new
      blocking_state.state_name = "PAUSED"
      blocking_state.service = "crowdchurn-subscription"
      blocking_state.is_block_change = false
      blocking_state.is_block_entitlement = true
      blocking_state.is_block_billing = true

      KillBill::Client::Model::Account.set_blocking_state(
        killbill_subscription.account_id,
        blocking_state,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      KillbillSubscription.new(killbill_subscription)
    end
  end

  def resume_subscription(subscription_id)
    with_killbill_error_handler do
      killbill_subscription = KillBill::Client::Model::Subscription.find_by_external_key(
        subscription_id,
        killbill_options
      )

      return nil unless killbill_subscription

      blocking_state = KillBill::Client::Model::BlockingState.new
      blocking_state.state_name = "ACTIVE"
      blocking_state.service = "crowdchurn-subscription"
      blocking_state.is_block_change = false
      blocking_state.is_block_entitlement = false
      blocking_state.is_block_billing = false

      KillBill::Client::Model::Account.set_blocking_state(
        killbill_subscription.account_id,
        blocking_state,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      KillbillSubscription.new(killbill_subscription)
    end
  end

  def change_plan(subscription_id, new_plan_name:, change_immediately: true)
    with_killbill_error_handler do
      killbill_subscription = KillBill::Client::Model::Subscription.find_by_external_key(
        subscription_id,
        killbill_options
      )

      return nil unless killbill_subscription

      policy = change_immediately ? "IMMEDIATE" : "END_OF_TERM"

      killbill_subscription.change_plan(
        { productName: extract_product_name(new_plan_name),
          billingPeriod: extract_billing_period(new_plan_name),
          priceList: "DEFAULT" },
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        nil,
        policy,
        nil,
        false,
        killbill_options
      )

      KillbillSubscription.new(killbill_subscription)
    end
  end

  def get_invoices(account_id)
    with_killbill_error_handler do
      invoices = KillBill::Client::Model::Invoice.find_all_by_account_id(
        account_id,
        true,
        killbill_options
      )

      invoices.map { |invoice| KillbillInvoice.new(invoice) }
    end
  end

  def get_invoice(invoice_id)
    with_killbill_error_handler do
      invoice = KillBill::Client::Model::Invoice.find_by_id(
        invoice_id,
        true,
        killbill_options
      )

      KillbillInvoice.new(invoice) if invoice
    end
  end

  def pay_invoice(invoice_id, payment_method_id: nil)
    with_killbill_error_handler do
      invoice = KillBill::Client::Model::Invoice.find_by_id(
        invoice_id,
        false,
        killbill_options
      )

      return nil unless invoice

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

  def get_account_subscriptions(account_id)
    with_killbill_error_handler do
      bundles = KillBill::Client::Model::Bundle.find_all_by_account_id(
        account_id,
        killbill_options
      )

      bundles.flat_map do |bundle|
        bundle.subscriptions.map { |sub| KillbillSubscription.new(sub) }
      end
    end
  end

  def add_payment_method(account_id, payment_method_data)
    with_killbill_error_handler do
      payment_method = KillBill::Client::Model::PaymentMethod.new
      payment_method.account_id = account_id
      payment_method.plugin_name = payment_method_data[:plugin_name] || "__EXTERNAL_PAYMENT__"
      payment_method.plugin_info = payment_method_data[:plugin_info]
      payment_method.is_default = payment_method_data[:is_default] || true

      created_payment_method = payment_method.create(
        true,
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      created_payment_method
    end
  end

  def sync_subscription_with_killbill(subscription)
    killbill_subscription = get_subscription(subscription.external_id)
    return nil unless killbill_subscription

    case killbill_subscription.state
    when SUBSCRIPTION_STATE_CANCELLED
      subscription.cancel_effective_immediately! unless subscription.cancelled_at.present?
    when SUBSCRIPTION_STATE_BLOCKED
      subscription.deactivate! unless subscription.deactivated_at.present?
    end

    killbill_subscription
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
        reason: "CrowdChurn subscription management",
        comment: "Automated via CrowdChurn"
      }
    end

    def get_or_create_account(subscription)
      email = subscription.email
      external_key = "crowdchurn_#{subscription.user&.external_id || subscription.id}"

      begin
        account = KillBill::Client::Model::Account.find_by_external_key(
          external_key,
          false,
          false,
          killbill_options
        )
        return account.account_id if account
      rescue KillBill::Client::API::NotFound
        # Account doesn't exist, create it
      end

      account = KillBill::Client::Model::Account.new
      account.external_key = external_key
      account.email = email
      account.name = subscription.original_purchase&.full_name
      account.currency = resolve_account_currency(subscription)

      created_account = account.create(
        killbill_options[:username],
        killbill_options[:reason],
        killbill_options[:comment],
        killbill_options
      )

      created_account.account_id
    end

    def generate_plan_name(subscription)
      product_name = subscription.link.name.parameterize.underscore
      recurrence = subscription.recurrence
      billing_period = recurrence_to_billing_period(recurrence)

      "#{product_name}-#{billing_period.downcase}"
    end

    def recurrence_to_billing_period(recurrence)
      case recurrence
      when BasePrice::Recurrence::MONTHLY
        BILLING_PERIOD_MONTHLY
      when BasePrice::Recurrence::YEARLY
        BILLING_PERIOD_ANNUAL
      when BasePrice::Recurrence::QUARTERLY
        BILLING_PERIOD_QUARTERLY
      else
        BILLING_PERIOD_MONTHLY
      end
    end

    def extract_product_name(plan_name)
      plan_name.split("-").first
    end

    def extract_billing_period(plan_name)
      period = plan_name.split("-").last.upcase
      %w[MONTHLY ANNUAL WEEKLY QUARTERLY].include?(period) ? period : BILLING_PERIOD_MONTHLY
    end

    def resolve_account_currency(subscription)
      # Use the subscription's billing_currency if set, otherwise fall back to the product's currency
      currency = subscription.billing_currency.presence || subscription.link&.price_currency_type
      (currency || Currency::USD).to_s.upcase
    end
end
