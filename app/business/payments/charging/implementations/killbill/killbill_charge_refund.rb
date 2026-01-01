# frozen_string_literal: true

# Represents a refund transaction in Kill Bill
#
# IMPORTANT: Cryptocurrency vs Fiat Refund Behavior
#
# Cryptocurrency refunds are NET (not GROSS):
# - Original blockchain transaction fees are NOT refunded
# - These fees were paid to miners/validators and are irrecoverable by design
# - The customer receives the payment amount minus any network fees
# - This is an inherent limitation of blockchain technology, not a policy choice
#
# Fiat refunds are typically GROSS:
# - Payment processor fees may be reversed (depends on processor policy)
# - The customer receives the full original payment amount
# - Gumroad's fee portion is also refunded proportionally
#
class KillbillChargeRefund < ChargeRefund
  attr_reader :killbill_payment, :refund_transaction, :is_cryptocurrency

  # Public: Create a ChargeRefund from a Kill Bill Payment and refund transaction
  #
  # For cryptocurrency refunds, this represents a credit transaction sent to the
  # customer's wallet, since crypto transactions cannot be reversed.
  # Note: Crypto refunds are NET - blockchain transaction fees are not recoverable.
  def initialize(killbill_payment, refund_transaction, is_cryptocurrency: false)
    @killbill_payment = killbill_payment
    @refund_transaction = refund_transaction
    @is_cryptocurrency = is_cryptocurrency

    self.charge_processor_id = KillbillChargeProcessor.charge_processor_id
    self.id = refund_transaction&.transaction_id
    self.charge_id = killbill_payment&.payment_id

    self.flow_of_funds = build_flow_of_funds
  end

  # Returns true if this refund was for a cryptocurrency payment
  def cryptocurrency_refund?
    @is_cryptocurrency
  end

  private
    def build_flow_of_funds
      return nil unless refund_transaction.present?

      currency = refund_transaction.currency&.downcase || Currency::USD
      refund_amount_cents = (refund_transaction.amount.to_f * 100).to_i

      # For refunds, amounts are negative
      issued_amount = FlowOfFunds::Amount.new(
        currency: currency,
        cents: -1 * refund_amount_cents
      )

      settled_amount = FlowOfFunds::Amount.new(
        currency: currency,
        cents: -1 * refund_amount_cents
      )

      # Cryptocurrency refunds are NET - blockchain transaction fees are not recoverable
      # Fiat refunds are GROSS - processor fees may be reversed
      gumroad_amount = if is_cryptocurrency
        # NET refund: No fee reversal for crypto - original blockchain fees are lost
        # The customer receives only the payment amount, not the network fees they paid
        FlowOfFunds::Amount.new(currency: currency, cents: 0)
      else
        # GROSS refund: For fiat refunds, Gumroad's fee portion is also refunded
        gumroad_fee_cents = extract_gumroad_fee_refund
        FlowOfFunds::Amount.new(currency: currency, cents: -1 * gumroad_fee_cents)
      end

      FlowOfFunds.new(
        issued_amount: issued_amount,
        settled_amount: settled_amount,
        gumroad_amount: gumroad_amount
      )
    end

    def extract_gumroad_fee_refund
      # Try to extract the Gumroad fee that was refunded from transaction properties
      refund_transaction.properties&.each do |prop|
        return prop["value"].to_i if prop["key"] == "gumroad_fee_refund_cents"
      end

      # If not specified, calculate proportionally based on original fee
      original_fee = extract_original_gumroad_fee
      return 0 if original_fee.zero?

      original_amount = (killbill_payment.purchased_amount.to_f * 100).to_i
      refund_amount = (refund_transaction.amount.to_f * 100).to_i

      return original_fee if refund_amount >= original_amount

      # Proportional fee refund for partial refunds
      (original_fee * refund_amount.to_f / original_amount).round
    end

    def extract_original_gumroad_fee
      killbill_payment.transactions&.each do |transaction|
        next unless transaction.transaction_type == "PURCHASE"

        transaction.properties&.each do |prop|
          return prop["value"].to_i if prop["key"] == "gumroad_fee_cents"
        end
      end

      0
    end
end
