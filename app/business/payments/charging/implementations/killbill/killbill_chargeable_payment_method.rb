# frozen_string_literal: true

# Represents a Kill Bill payment method that can be charged
class KillbillChargeablePaymentMethod
  attr_reader :payment_method_id, :account_id, :zip_code, :product_permalink
  attr_accessor :is_cryptocurrency

  def initialize(payment_method_id, account_id: nil, zip_code: nil, product_permalink: nil, is_cryptocurrency: false)
    @payment_method_id = payment_method_id
    @account_id = account_id
    @zip_code = zip_code
    @product_permalink = product_permalink
    @is_cryptocurrency = is_cryptocurrency
  end

  def charge_processor_id
    KillbillChargeProcessor.charge_processor_id
  end

  def is_cryptocurrency?
    @is_cryptocurrency
  end

  # Prepare the payment method for charging
  # This loads additional details from Kill Bill if needed
  def prepare!
    return if @prepared

    options = killbill_options
    payment_method = KillBillClient::Model::PaymentMethod.find_by_id(
      payment_method_id,
      true,
      options
    )

    if payment_method.present?
      @account_id ||= payment_method.account_id
      extract_payment_method_details(payment_method)
    end

    @prepared = true
  rescue StandardError => e
    Rails.logger.error("Failed to prepare Kill Bill payment method: #{e.message}")
  end

  attr_reader :country

  def requires_mandate?
    false
  end

  attr_reader :fingerprint

  attr_reader :last4

  attr_reader :card_type

  attr_reader :expiry_month

  attr_reader :expiry_year

  private
    def killbill_options
      {
        base_uri: ENV.fetch("KILLBILL_URL", nil),
        username: ENV.fetch("KILLBILL_USER", "admin"),
        password: ENV.fetch("KILLBILL_PASSWORD", "password"),
        api_key: ENV.fetch("KILLBILL_API_KEY", "bob"),
        api_secret: ENV.fetch("KILLBILL_API_SECRET", "lazar")
      }
    end

    def extract_payment_method_details(payment_method)
      # Extract details from plugin info if available
      plugin_info = payment_method.plugin_info
      return unless plugin_info.present?

      properties = plugin_info.properties || []
      properties.each do |prop|
        case prop.key
        when "card_country", "country"
          @country = prop.value
        when "card_fingerprint", "fingerprint"
          @fingerprint = prop.value
        when "card_last4", "last4"
          @last4 = prop.value
        when "card_type", "type"
          @card_type = prop.value
        when "card_expiry_month", "expiry_month"
          @expiry_month = prop.value.to_i
        when "card_expiry_year", "expiry_year"
          @expiry_year = prop.value.to_i
        when "is_cryptocurrency"
          @is_cryptocurrency = prop.value == "true"
        end
      end
    end
end
