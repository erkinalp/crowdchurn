# frozen_string_literal: true

# Represents a Kill Bill credit card that can be charged
# Used for recurring charges where we have stored card details
class KillbillChargeableCreditCard
  attr_reader :merchant_account, :reusable_token, :payment_method_id, :fingerprint,
              :last4, :number_length, :visual, :expiry_month, :expiry_year,
              :card_type, :country, :zip_code
  attr_accessor :is_cryptocurrency

  def initialize(merchant_account, reusable_token, payment_method_id, fingerprint,
                 last4, number_length, visual, expiry_month, expiry_year,
                 card_type, country, zip_code)
    @merchant_account = merchant_account
    @reusable_token = reusable_token
    @payment_method_id = payment_method_id
    @fingerprint = fingerprint
    @last4 = last4
    @number_length = number_length
    @visual = visual
    @expiry_month = expiry_month
    @expiry_year = expiry_year
    @card_type = card_type
    @country = country
    @zip_code = zip_code
    @is_cryptocurrency = false
  end

  def charge_processor_id
    KillbillChargeProcessor.charge_processor_id
  end

  def account_id
    merchant_account&.charge_processor_merchant_id
  end

  def is_cryptocurrency?
    @is_cryptocurrency
  end

  def prepare!
    # Credit card details are already loaded, nothing to prepare
  end

  def requires_mandate?
    false
  end
end
