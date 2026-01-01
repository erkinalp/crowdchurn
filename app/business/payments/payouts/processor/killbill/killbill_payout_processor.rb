# frozen_string_literal: true

class KillbillPayoutProcessor
  include KillbillErrorHandler
  extend CurrencyHelper

  DISPLAY_NAME = "Kill Bill"

  DEFAULT_KILLBILL_URL = ENV.fetch("KILLBILL_URL", nil)
  DEFAULT_KILLBILL_USER = ENV.fetch("KILLBILL_USER", nil)
  DEFAULT_KILLBILL_PASSWORD = ENV.fetch("KILLBILL_PASSWORD", nil)
  DEFAULT_KILLBILL_API_KEY = ENV.fetch("KILLBILL_API_KEY", nil)
  DEFAULT_KILLBILL_API_SECRET = ENV.fetch("KILLBILL_API_SECRET", nil)

  TRANSACTION_TYPE_CREDIT = "CREDIT"

  def self.payout_processor_id
    "killbill"
  end

  def self.is_user_payable(user, amount_payable_usd_cents, add_comment: false, from_admin: false, payout_type: Payouts::PAYOUT_TYPE_STANDARD)
    payout_date = Time.current.to_fs(:formatted_date_full_month)

    if user.payments.processing.any?
      user.add_payout_note(content: "Payout on #{payout_date} was skipped because there was already a payout in processing.") if add_comment
      return false
    end

    return false unless user.killbill_merchant_account.present?

    killbill_account = user.killbill_merchant_account
    return false unless killbill_account.charge_processor_merchant_id.present?

    if payout_type == Payouts::PAYOUT_TYPE_INSTANT
      user.add_payout_note(content: "Kill Bill does not support instant payouts.") if add_comment
      return false
    end

    true
  end

  def self.has_valid_payout_info?(user)
    return false unless user.killbill_merchant_account.present?

    killbill_account = user.killbill_merchant_account
    killbill_account.charge_processor_merchant_id.present?
  end

  def self.is_balance_payable(balance)
    return false unless balance.merchant_account.present?

    holder = balance.merchant_account.holder_of_funds
    case holder
    when HolderOfFunds::CREATOR
      balance.holding_currency == balance.merchant_account.currency
    when HolderOfFunds::GUMROAD
      true
    else
      false
    end
  end

  def self.prepare_payment_and_set_amount(payment, balances)
    payment.currency = Currency::USD
    payment.amount_cents = balances.sum(&:holding_amount_cents)
    []
  rescue StandardError => e
    failed = true
    Bugsnag.notify(e)
    [e.message]
  ensure
    payment.mark_failed! if failed
  end

  def self.enqueue_payments(user_ids, date_string, payout_type: Payouts::PAYOUT_TYPE_STANDARD)
    user_ids.each do |user_id|
      PayoutUsersWorker.perform_async(date_string, PayoutProcessorType::KILLBILL, user_id, payout_type)
    end
  end

  def self.process_payments(payments)
    payments.each do |payment|
      perform_payment(payment)
    end
  end

  def self.perform_payment(payment)
    processor = new
    processor.perform_payment_instance(payment)
  end

  def perform_payment_instance(payment)
    with_killbill_error_handler do
      user = payment.user
      merchant_account = user.killbill_merchant_account

      unless merchant_account.present?
        payment.mark_failed!
        return ["Kill Bill merchant account not found for user"]
      end

      options = killbill_options(merchant_account)
      account_id = merchant_account.charge_processor_merchant_id

      is_crypto = is_cryptocurrency_payout?(payment)

      if is_crypto
        perform_crypto_payout(payment, account_id, options)
      else
        perform_fiat_payout(payment, account_id, options)
      end

      payment.save!
      []
    end
  rescue StandardError => e
    failed = true
    Bugsnag.notify(e)
    Rails.logger.error("Kill Bill Payouts: Payout errors for user with id: #{payment.user_id} #{e.message}")
    [e.message]
  ensure
    Rails.logger.info("Kill Bill Payouts: Payout of #{payment.amount_cents} attempted for user with id: #{payment.user_id}")
    payment.mark_failed! if failed
  end

  private
    def killbill_options(merchant_account = nil)
      instance_url = killbill_instance_url(merchant_account)

      unless instance_url.present?
        raise ChargeProcessorInvalidRequestError.new(
          "Kill Bill instance URL not configured. Set KILLBILL_URL environment variable " \
          "or configure a Kill Bill instance URL on the merchant account."
        )
      end

      configure_killbill_client(instance_url)

      {
        username: killbill_username(merchant_account),
        password: killbill_password(merchant_account),
        api_key: killbill_api_key(merchant_account),
        api_secret: killbill_api_secret(merchant_account),
        reason: "CrowdChurn payout processing",
        comment: "Automated payout via CrowdChurn"
      }
    end

    def killbill_instance_url(merchant_account)
      merchant_account&.killbill_instance_url.presence || DEFAULT_KILLBILL_URL
    end

    def killbill_username(merchant_account)
      merchant_account&.killbill_username.presence || DEFAULT_KILLBILL_USER
    end

    def killbill_password(merchant_account)
      merchant_account&.killbill_password.presence || DEFAULT_KILLBILL_PASSWORD
    end

    def killbill_api_key(merchant_account)
      merchant_account&.killbill_api_key.presence || DEFAULT_KILLBILL_API_KEY
    end

    def killbill_api_secret(merchant_account)
      merchant_account&.killbill_api_secret.presence || DEFAULT_KILLBILL_API_SECRET
    end

    def configure_killbill_client(instance_url)
      KillBill::Client.url = instance_url
    end

    def is_cryptocurrency_payout?(payment)
      payment.json_data&.dig("is_cryptocurrency") == true ||
        payment.bank_account&.respond_to?(:is_cryptocurrency?) && payment.bank_account.is_cryptocurrency?
    end

    def perform_fiat_payout(payment, account_id, options)
      amount = payment.amount_cents / 100.0

      properties = build_payout_properties(
        payment: payment,
        is_crypto: false
      )

      credit_transaction = KillBill::Client::Model::PaymentTransaction.new
      credit_transaction.amount = amount
      credit_transaction.currency = payment.currency.upcase
      credit_transaction.transaction_type = TRANSACTION_TYPE_CREDIT
      credit_transaction.transaction_external_key = "payout_#{payment.external_id}_#{Time.now.to_i}"

      payout_payment = KillBill::Client::Model::Payment.new
      payout_payment.account_id = account_id
      payout_payment.payment_external_key = "payout_#{payment.external_id}"
      payout_payment.transactions = [credit_transaction]

      created_payment = payout_payment.create(
        true,
        options[:username],
        options[:reason],
        options[:comment],
        options,
        properties
      )

      payment.killbill_payment_id = created_payment.payment_id
      payment.killbill_transaction_id = created_payment.transactions&.last&.transaction_id
    end

    def perform_crypto_payout(payment, account_id, options)
      wallet_address = extract_wallet_address(payment)

      unless wallet_address.present?
        raise ChargeProcessorInvalidRequestError.new(
          "Cannot process cryptocurrency payout: wallet address not found. " \
          "Please provide a wallet address for the payout."
        )
      end

      amount = payment.amount_cents / 100.0

      properties = build_payout_properties(
        payment: payment,
        is_crypto: true,
        wallet_address: wallet_address
      )

      credit_transaction = KillBill::Client::Model::PaymentTransaction.new
      credit_transaction.amount = amount
      credit_transaction.currency = payment.currency.upcase
      credit_transaction.transaction_type = TRANSACTION_TYPE_CREDIT
      credit_transaction.transaction_external_key = "crypto_payout_#{payment.external_id}_#{Time.now.to_i}"

      payout_payment = KillBill::Client::Model::Payment.new
      payout_payment.account_id = account_id
      payout_payment.payment_external_key = "crypto_payout_#{payment.external_id}"
      payout_payment.transactions = [credit_transaction]

      created_payment = payout_payment.create(
        true,
        options[:username],
        options[:reason],
        options[:comment],
        options,
        properties
      )

      payment.killbill_payment_id = created_payment.payment_id
      payment.killbill_transaction_id = created_payment.transactions&.last&.transaction_id
      payment.json_data ||= {}
      payment.json_data["wallet_address"] = wallet_address
      payment.json_data["is_cryptocurrency_payout"] = true
      payment.json_data["payout_type"] = "net"
    end

    def build_payout_properties(payment:, is_crypto:, wallet_address: nil)
      properties = []

      properties << { key: "payment_external_id", value: payment.external_id }
      properties << { key: "user_id", value: payment.user_id.to_s }
      properties << { key: "payout_period_end_date", value: payment.payout_period_end_date.to_s }

      if is_crypto
        properties << { key: "is_cryptocurrency_payout", value: "true" }
        properties << { key: "wallet_address", value: wallet_address } if wallet_address.present?
        properties << { key: "payout_type", value: "net" }
      end

      properties
    end

    def extract_wallet_address(payment)
      payment.json_data&.dig("wallet_address") ||
        payment.bank_account&.respond_to?(:wallet_address) && payment.bank_account.wallet_address
    end
end
