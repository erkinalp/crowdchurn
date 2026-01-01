# frozen_string_literal: true

class KillbillChargeProcessor
  include KillbillErrorHandler
  extend CurrencyHelper

  DISPLAY_NAME = "Kill Bill"

  # Kill Bill transaction statuses that indicate success
  # https://docs.killbill.io/latest/userguide_payment.html
  VALID_TRANSACTION_STATUSES = %w(success pending).freeze

  # Refund reason for fraudulent transactions
  REFUND_REASON_FRAUDULENT = "fraudulent"

  # Transaction types supported by Kill Bill
  TRANSACTION_TYPE_PURCHASE = "PURCHASE"
  TRANSACTION_TYPE_AUTHORIZE = "AUTHORIZE"
  TRANSACTION_TYPE_CAPTURE = "CAPTURE"
  TRANSACTION_TYPE_REFUND = "REFUND"
  TRANSACTION_TYPE_CREDIT = "CREDIT"

  # Default Kill Bill instance configuration
  # These are used when no merchant-specific instance is configured
  # IMPORTANT: Set these environment variables in production - do not use defaults
  DEFAULT_KILLBILL_URL = ENV.fetch("KILLBILL_URL", nil)
  DEFAULT_KILLBILL_USER = ENV.fetch("KILLBILL_USER", nil)
  DEFAULT_KILLBILL_PASSWORD = ENV.fetch("KILLBILL_PASSWORD", nil)
  DEFAULT_KILLBILL_API_KEY = ENV.fetch("KILLBILL_API_KEY", nil)
  DEFAULT_KILLBILL_API_SECRET = ENV.fetch("KILLBILL_API_SECRET", nil)

  def self.charge_processor_id
    "killbill"
  end

  def merchant_migrated?(merchant_account)
    merchant_account&.charge_processor_id == self.class.charge_processor_id
  end

  def get_chargeable_for_params(params, _gumroad_guid)
    return nil unless params[:killbill_payment_method_id].present?

    zip_code = params[:cc_zipcode] if params[:cc_zipcode_required]
    product_permalink = params[:product_permalink]

    KillbillChargeablePaymentMethod.new(
      params[:killbill_payment_method_id],
      account_id: params[:killbill_account_id],
      zip_code: zip_code,
      product_permalink: product_permalink
    )
  end

  def get_chargeable_for_data(reusable_token, payment_method_id, fingerprint,
                              _stripe_setup_intent_id, _stripe_payment_intent_id,
                              last4, number_length, visual, expiry_month, expiry_year,
                              card_type, country, zip_code = nil, merchant_account: nil)
    KillbillChargeableCreditCard.new(
      merchant_account,
      reusable_token,
      payment_method_id,
      fingerprint,
      last4,
      number_length,
      visual,
      expiry_month,
      expiry_year,
      card_type,
      country,
      zip_code
    )
  end

  # Search for a payment by purchase reference
  def search_charge(purchase:)
    with_killbill_error_handler do
      account_id = purchase.merchant_account&.charge_processor_merchant_id
      return nil unless account_id.present?

      options = killbill_options(purchase.merchant_account)
      payments = KillBill::Client::Model::Payment.find_all_by_search_key(
        purchase.external_id,
        options
      )

      payments&.first
    end
  end

  def get_charge(charge_id, merchant_account: nil)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)
      payment = KillBill::Client::Model::Payment.find_by_id(charge_id, true, true, options)

      get_charge_object(payment)
    end
  end

  def get_charge_object(payment)
    KillbillCharge.new(payment)
  end

  def get_charge_intent(payment_id, merchant_account: nil)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)
      payment = KillBill::Client::Model::Payment.find_by_id(payment_id, true, true, options)

      KillbillChargeIntent.new(payment: payment, merchant_account: merchant_account)
    end
  end

  # Kill Bill doesn't have a separate setup intent concept like Stripe
  # We use the payment method directly for future charges
  def setup_future_charges!(merchant_account, chargeable, mandate_options: nil)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)

      # In Kill Bill, payment methods are stored on the account
      # and can be reused for future charges without a separate setup intent
      payment_method = KillBill::Client::Model::PaymentMethod.find_by_id(
        chargeable.payment_method_id,
        true,
        options
      )

      KillbillSetupIntent.new(payment_method)
    end
  end

  # Creates a payment transaction in Kill Bill
  # This is equivalent to Stripe's create_payment_intent_or_charge!
  def create_payment_intent_or_charge!(merchant_account, chargeable, amount_cents, amount_for_gumroad_cents, reference,
                                       description, metadata: nil, statement_description: nil,
                                       transfer_group: nil, off_session: true, setup_future_charges: false, mandate_options: nil)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)

      account_id = chargeable.account_id || merchant_account&.charge_processor_merchant_id
      raise ChargeProcessorInvalidRequestError.new("Kill Bill account ID is required") unless account_id.present?

      payment_method_id = chargeable.payment_method_id
      raise ChargeProcessorInvalidRequestError.new("Kill Bill payment method ID is required") unless payment_method_id.present?

      # Build transaction properties
      properties = build_transaction_properties(
        reference: reference,
        description: description,
        metadata: metadata,
        statement_description: statement_description,
        amount_for_gumroad_cents: amount_for_gumroad_cents,
        is_crypto: chargeable.is_cryptocurrency?
      )

      # Create the payment transaction
      # Kill Bill uses cents for amount, currency is USD by default
      transaction = KillBill::Client::Model::PaymentTransaction.new
      transaction.amount = amount_cents / 100.0
      transaction.currency = Currency::USD.upcase
      transaction.transaction_external_key = reference
      transaction.transaction_type = TRANSACTION_TYPE_PURCHASE

      # Create payment with the transaction
      payment = KillBill::Client::Model::Payment.new
      payment.account_id = account_id
      payment.payment_method_id = payment_method_id
      payment.payment_external_key = transfer_group || reference
      payment.transactions = [transaction]

      # Execute the payment
      created_payment = payment.create(
        true, # auth
        options[:username],
        options[:reason],
        options[:comment],
        options,
        properties
      )

      KillbillChargeIntent.new(payment: created_payment, merchant_account: merchant_account)
    end
  end

  def confirm_payment_intent!(merchant_account, charge_intent_id)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)
      payment = KillBill::Client::Model::Payment.find_by_id(charge_intent_id, true, true, options)

      # In Kill Bill, payments are typically auto-confirmed
      # This method exists for API compatibility with Stripe
      KillbillChargeIntent.new(payment: payment, merchant_account: merchant_account)
    end
  end

  def cancel_payment_intent!(merchant_account, charge_intent_id)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)
      payment = KillBill::Client::Model::Payment.find_by_id(charge_intent_id, true, true, options)

      # Void the payment if it hasn't been captured
      void_transaction = KillBill::Client::Model::PaymentTransaction.new
      void_transaction.payment_id = payment.payment_id
      void_transaction.transaction_type = "VOID"

      payment.void(
        options[:username],
        options[:reason],
        options[:comment],
        options
      )
    end
  end

  def get_refund(refund_id, merchant_account: nil)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)

      # In Kill Bill, refunds are transactions on a payment
      # We need to find the payment that contains this refund transaction
      payment = KillBill::Client::Model::Payment.find_by_transaction_id(refund_id, true, true, options)

      refund_transaction = payment.transactions.find { |t| t.transaction_id == refund_id }

      KillbillChargeRefund.new(payment, refund_transaction)
    end
  end

  # Refund a charge in Kill Bill
  # For cryptocurrency payments, this creates a credit transaction to the customer's wallet
  def refund!(charge_id, amount_cents: nil, merchant_account: nil, reverse_transfer: true, is_for_fraud: nil, **_args)
    with_killbill_error_handler do
      options = killbill_options(merchant_account)
      payment = KillBill::Client::Model::Payment.find_by_id(charge_id, true, true, options)

      # Determine if this is a cryptocurrency payment
      is_crypto_payment = is_cryptocurrency_payment?(payment)

      if is_crypto_payment
        # For cryptocurrency payments, we create a credit transaction
        # since crypto transactions cannot be reversed
        refund_cryptocurrency_payment!(payment, amount_cents, options, is_for_fraud)
      else
        # Standard refund for fiat payments
        refund_fiat_payment!(payment, amount_cents, options, is_for_fraud)
      end
    end
  rescue KillBill::Client::API::BadRequest => e
    if e.message.include?("already been refunded")
      raise ChargeProcessorAlreadyRefundedError.new(
        "Kill Bill charge was already refunded. Kill Bill response: #{e.message}",
        original_error: e
      )
    end
    raise ChargeProcessorInvalidRequestError.new(original_error: e)
  end

  def holder_of_funds(merchant_account)
    # Kill Bill can be configured to hold funds in different ways
    # By default, we assume funds are held by the platform (Gumroad)
    # For merchant accounts with their own Kill Bill tenant, funds are held by the creator
    if merchant_account&.is_a_killbill_merchant_account?
      HolderOfFunds::CREATOR
    else
      HolderOfFunds::GUMROAD
    end
  end

  def transaction_url(charge_id, merchant_account: nil)
    # Kill Bill admin UI (Kaui) URL for viewing transactions
    # Uses the merchant-specific instance URL if configured
    killbill_base_url = killbill_instance_url(merchant_account) || "http://localhost:8080"
    "#{killbill_base_url}/kaui/payments/#{charge_id}"
  end

  # Get the Kill Bill instance URL for the merchant account (public for transaction_url)
  def killbill_instance_url(merchant_account)
    merchant_account&.killbill_instance_url.presence || DEFAULT_KILLBILL_URL
  end

  # Handle Kill Bill webhook events
  def self.handle_killbill_event(killbill_event)
    event_type = killbill_event["eventType"]

    case event_type
    when "PAYMENT_SUCCESS", "PAYMENT_FAILED"
      handle_payment_event(killbill_event)
    when "PAYMENT_REFUND"
      handle_refund_event(killbill_event)
    when "PAYMENT_CHARGEBACK"
      handle_chargeback_event(killbill_event)
    end
  end

  private
    # Build Kill Bill API options for the given merchant account
    # Supports multiple simultaneous Kill Bill instances:
    # - Each merchant can have their own self-hosted Kill Bill instance
    # - Merchant accounts store instance URL, credentials, and tenant info
    # - Falls back to default instance from environment variables
    def killbill_options(merchant_account = nil)
      # Get instance-specific configuration from merchant account or defaults
      instance_url = killbill_instance_url(merchant_account)

      # Validate that we have a Kill Bill instance configured
      unless instance_url.present?
        raise ChargeProcessorInvalidRequestError.new(
          "Kill Bill instance URL not configured. Set KILLBILL_URL environment variable " \
          "or configure a Kill Bill instance URL on the merchant account."
        )
      end

      # Configure the Kill Bill client to use the correct instance
      configure_killbill_client(instance_url)

      {
        username: killbill_username(merchant_account),
        password: killbill_password(merchant_account),
        api_key: killbill_api_key(merchant_account),
        api_secret: killbill_api_secret(merchant_account),
        reason: "CrowdChurn payment processing",
        comment: "Automated payment via CrowdChurn"
      }
    end

    def killbill_username(merchant_account)
      merchant_account&.killbill_username.presence || DEFAULT_KILLBILL_USER
    end

    def killbill_password(merchant_account)
      merchant_account&.killbill_password.presence || DEFAULT_KILLBILL_PASSWORD
    end

    def killbill_api_key(merchant_account)
      # API key identifies the tenant in Kill Bill
      # Each whitelabel instance can have multiple tenants
      merchant_account&.killbill_api_key.presence || DEFAULT_KILLBILL_API_KEY
    end

    def killbill_api_secret(merchant_account)
      merchant_account&.killbill_api_secret.presence || DEFAULT_KILLBILL_API_SECRET
    end

    # Configure the Kill Bill client to connect to the specified instance
    # This is called before each API request to ensure we're using the correct instance
    def configure_killbill_client(instance_url)
      # The killbill-client gem uses a global configuration
      # We need to set it per-request to support multiple instances
      KillBill::Client.url = instance_url
    end

    def build_transaction_properties(reference:, description:, metadata:, statement_description:, amount_for_gumroad_cents:, is_crypto:)
      properties = []

      properties << { key: "reference", value: reference } if reference.present?
      properties << { key: "description", value: description } if description.present?
      properties << { key: "statement_description", value: statement_description } if statement_description.present?
      properties << { key: "gumroad_fee_cents", value: amount_for_gumroad_cents.to_s } if amount_for_gumroad_cents.present?
      properties << { key: "is_cryptocurrency", value: is_crypto.to_s } if is_crypto

      if metadata.present?
        metadata.each do |key, value|
          properties << { key: "metadata_#{key}", value: value.to_s }
        end
      end

      properties
    end

    def is_cryptocurrency_payment?(payment)
      # Check if the payment method or transaction properties indicate cryptocurrency
      return false unless payment.present?

      # Check transaction properties for crypto flag
      payment.transactions&.any? do |transaction|
        transaction.properties&.any? { |p| p["key"] == "is_cryptocurrency" && p["value"] == "true" }
      end
    end

    # Refund a cryptocurrency payment by creating a credit transaction
    # Since crypto transactions cannot be reversed, we send new funds to the customer
    #
    # IMPORTANT: Cryptocurrency refunds are NET, not GROSS
    # - The original blockchain transaction fees are NOT refunded
    # - These fees were paid to miners/validators and are irrecoverable
    # - The refund amount is the payment amount minus any transaction fees
    # - This is different from fiat refunds where processor fees may be reversed
    #
    # Example: Customer pays 0.01 BTC + 0.0001 BTC network fee
    # Refund sends: 0.01 BTC (the 0.0001 BTC fee is lost)
    def refund_cryptocurrency_payment!(payment, amount_cents, options, is_for_fraud)
      # Get the customer's wallet address from the original payment
      wallet_address = extract_wallet_address(payment)

      unless wallet_address.present?
        raise ChargeProcessorInvalidRequestError.new(
          "Cannot refund cryptocurrency payment: customer wallet address not found. " \
          "Please provide a wallet address for the refund."
        )
      end

      # Calculate refund amount
      original_amount_cents = (payment.purchased_amount * 100).to_i
      refund_amount_cents = amount_cents || original_amount_cents

      # Create a credit transaction to send funds back to the customer
      credit_transaction = KillBill::Client::Model::PaymentTransaction.new
      credit_transaction.payment_id = payment.payment_id
      credit_transaction.amount = refund_amount_cents / 100.0
      credit_transaction.currency = payment.currency
      credit_transaction.transaction_type = TRANSACTION_TYPE_CREDIT
      credit_transaction.transaction_external_key = "crypto_refund_#{payment.payment_id}_#{Time.now.to_i}"

      # Add properties for the crypto refund
      properties = [
        { key: "wallet_address", value: wallet_address },
        { key: "is_cryptocurrency_refund", value: "true" },
        { key: "original_payment_id", value: payment.payment_id }
      ]
      properties << { key: "refund_reason", value: REFUND_REASON_FRAUDULENT } if is_for_fraud

      # Execute the credit transaction
      payment.credit(
        credit_transaction.amount,
        payment.currency,
        credit_transaction.transaction_external_key,
        options[:username],
        options[:reason],
        options[:comment],
        options,
        properties
      )

      # Retrieve the updated payment with the refund transaction
      updated_payment = KillBill::Client::Model::Payment.find_by_id(payment.payment_id, true, true, options)
      refund_transaction = updated_payment.transactions.find { |t| t.transaction_type == TRANSACTION_TYPE_CREDIT }

      KillbillChargeRefund.new(updated_payment, refund_transaction, is_cryptocurrency: true)
    end

    # Standard refund for fiat (non-cryptocurrency) payments
    def refund_fiat_payment!(payment, amount_cents, options, is_for_fraud)
      # Calculate refund amount
      original_amount_cents = (payment.purchased_amount * 100).to_i
      refund_amount_cents = amount_cents || original_amount_cents
      refund_amount = refund_amount_cents / 100.0

      # Build refund properties
      properties = []
      properties << { key: "refund_reason", value: REFUND_REASON_FRAUDULENT } if is_for_fraud

      # Execute the refund
      payment.refund(
        refund_amount,
        payment.currency,
        "refund_#{payment.payment_id}_#{Time.now.to_i}",
        options[:username],
        options[:reason],
        options[:comment],
        options,
        properties
      )

      # Retrieve the updated payment with the refund transaction
      updated_payment = KillBill::Client::Model::Payment.find_by_id(payment.payment_id, true, true, options)
      refund_transaction = updated_payment.transactions.find { |t| t.transaction_type == TRANSACTION_TYPE_REFUND }

      KillbillChargeRefund.new(updated_payment, refund_transaction)
    end

    def extract_wallet_address(payment)
      # Try to find wallet address in payment properties
      payment.transactions&.each do |transaction|
        transaction.properties&.each do |prop|
          return prop["value"] if prop["key"] == "wallet_address"
        end
      end

      # Try to find wallet address in payment method
      # This would be stored when the customer set up their crypto payment method
      nil
    end

    def self.handle_payment_event(killbill_event)
      event = ChargeEvent.new
      event.charge_processor_id = charge_processor_id
      event.charge_event_id = killbill_event["eventId"]
      event.charge_id = killbill_event["objectId"]
      event.created_at = DateTime.parse(killbill_event["eventDate"])
      event.comment = killbill_event["eventType"]

      event.type = case killbill_event["eventType"]
                   when "PAYMENT_SUCCESS"
                     ChargeEvent::TYPE_CHARGE_SUCCEEDED
                   when "PAYMENT_FAILED"
                     ChargeEvent::TYPE_INFORMATIONAL
                   else
                     ChargeEvent::TYPE_INFORMATIONAL
      end

      ChargeProcessor.handle_event(event)
    end

    def self.handle_refund_event(killbill_event)
      event = ChargeEvent.new
      event.charge_processor_id = charge_processor_id
      event.charge_event_id = killbill_event["eventId"]
      event.charge_id = killbill_event["objectId"]
      event.refund_id = killbill_event["transactionId"]
      event.created_at = DateTime.parse(killbill_event["eventDate"])
      event.comment = killbill_event["eventType"]
      event.type = ChargeEvent::TYPE_CHARGE_REFUND_UPDATED

      ChargeProcessor.handle_event(event)
    end

    def self.handle_chargeback_event(killbill_event)
      event = ChargeEvent.new
      event.charge_processor_id = charge_processor_id
      event.charge_event_id = killbill_event["eventId"]
      event.charge_id = killbill_event["objectId"]
      event.created_at = DateTime.parse(killbill_event["eventDate"])
      event.comment = killbill_event["eventType"]
      event.type = ChargeEvent::TYPE_DISPUTE_FORMALIZED

      ChargeProcessor.handle_event(event)
    end
end
