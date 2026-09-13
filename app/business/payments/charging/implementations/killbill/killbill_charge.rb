# frozen_string_literal: true

class KillbillCharge < BaseProcessorCharge
  attr_reader :killbill_payment

  # Public: Create a BaseProcessorCharge from a Kill Bill Payment object
  def initialize(killbill_payment)
    @killbill_payment = killbill_payment

    self.charge_processor_id = KillbillChargeProcessor.charge_processor_id
    return if killbill_payment.nil?

    self.id = killbill_payment.payment_id
    self.status = determine_status(killbill_payment)
    self.refunded = killbill_payment.refunded_amount.to_f > 0
    self.disputed = has_chargeback?(killbill_payment)

    # Kill Bill doesn't expose processor fees directly in the payment object
    # Fees would be tracked separately or via plugin properties
    self.fee = nil
    self.fee_currency = nil

    self.flow_of_funds = build_flow_of_funds(killbill_payment)

    # Extract card details if available from payment method or transaction properties
    extract_payment_details(killbill_payment)
  end

  private
    def determine_status(payment)
      # Get the latest transaction status
      latest_transaction = payment.transactions&.last
      return "unknown" unless latest_transaction

      latest_transaction.status&.downcase || "unknown"
    end

    def has_chargeback?(payment)
      payment.transactions&.any? { |t| t.transaction_type == "CHARGEBACK" }
    end

    def build_flow_of_funds(payment)
      return nil unless payment.present?

      currency = payment.currency&.downcase || Currency::USD
      amount_cents = (payment.purchased_amount.to_f * 100).to_i

      # For Kill Bill, we build a simple flow of funds
      # More complex flows would require additional data from plugins
      issued_amount = FlowOfFunds::Amount.new(currency: currency, cents: amount_cents)
      settled_amount = FlowOfFunds::Amount.new(currency: currency, cents: amount_cents)
      gumroad_amount = FlowOfFunds::Amount.new(currency: currency, cents: extract_gumroad_fee(payment))

      FlowOfFunds.new(
        issued_amount: issued_amount,
        settled_amount: settled_amount,
        gumroad_amount: gumroad_amount
      )
    end

    def extract_gumroad_fee(payment)
      # Try to extract Gumroad fee from transaction properties
      payment.transactions&.each do |transaction|
        transaction.properties&.each do |prop|
          return prop.value.to_i if prop.key == "gumroad_fee_cents"
        end
      end

      # Default to 0 if not found
      0
    end

    def extract_payment_details(payment)
      # Try to extract card details from transaction properties
      # These would be set by the payment plugin during the transaction
      payment.transactions&.each do |transaction|
        transaction.properties&.each do |prop|
          case prop.key
          when "card_fingerprint"
            self.card_fingerprint = prop.value
          when "card_last4"
            self.card_last4 = prop.value
          when "card_type"
            self.card_type = prop.value
          when "card_expiry_month"
            self.card_expiry_month = prop.value.to_i
          when "card_expiry_year"
            self.card_expiry_year = prop.value.to_i
          when "card_country"
            self.card_country = prop.value
          when "card_zip_code"
            self.card_zip_code = prop.value
          when "risk_level"
            self.risk_level = prop.value
          end
        end
      end

      # Set card number length based on card type if available
      if card_type.present?
        self.card_number_length = ChargeableVisual.get_card_length_from_card_type(card_type)
      end
    end
end
