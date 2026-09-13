# frozen_string_literal: true

# Creates a ChargeIntent from Kill Bill Payment
# Kill Bill doesn't have a separate "intent" concept like Stripe's PaymentIntent,
# but we wrap the payment to maintain API compatibility
class KillbillChargeIntent < ChargeIntent
  attr_reader :killbill_payment, :merchant_account

  def initialize(payment:, merchant_account: nil)
    @killbill_payment = payment
    @merchant_account = merchant_account

    self.payment_intent = payment
    self.id = payment&.payment_id
    self.client_secret = nil # Kill Bill doesn't use client secrets

    load_charge(payment) if succeeded?
  end

  def succeeded?
    return false unless killbill_payment.present?

    latest_transaction = killbill_payment.transactions&.last
    return false unless latest_transaction

    latest_transaction.status&.upcase == "SUCCESS"
  end

  def requires_action?
    return false unless killbill_payment.present?

    latest_transaction = killbill_payment.transactions&.last
    return false unless latest_transaction

    # Kill Bill uses PENDING status for transactions that require additional action
    latest_transaction.status&.upcase == "PENDING"
  end

  def canceled?
    return false unless killbill_payment.present?

    latest_transaction = killbill_payment.transactions&.last
    return false unless latest_transaction

    # Check for voided transactions
    killbill_payment.transactions&.any? { |t| t.transaction_type == "VOID" && t.status&.upcase == "SUCCESS" }
  end

  def processing?
    return false unless killbill_payment.present?

    latest_transaction = killbill_payment.transactions&.last
    return false unless latest_transaction

    latest_transaction.status&.upcase == "PENDING"
  end

  private
    def load_charge(payment)
      self.charge = KillbillCharge.new(payment)
    end
end
