# frozen_string_literal: true

class KillbillPayment
  attr_reader :payment

  delegate :payment_id, :account_id, :payment_number, :payment_external_key,
           :auth_amount, :captured_amount, :purchased_amount, :refunded_amount,
           :credited_amount, :currency, :payment_method_id, :transactions,
           to: :payment, allow_nil: true

  PAYMENT_STATUS_SUCCESS = "SUCCESS"
  PAYMENT_STATUS_PENDING = "PENDING"
  PAYMENT_STATUS_FAILED = "PAYMENT_FAILURE"

  def initialize(payment)
    @payment = payment
  end

  def id
    payment_id
  end

  def amount_cents
    (purchased_amount.to_f * 100).to_i
  end

  def refunded_amount_cents
    (refunded_amount.to_f * 100).to_i
  end

  def status
    return PAYMENT_STATUS_FAILED unless transactions.present?

    last_transaction = transactions.last
    last_transaction&.status || PAYMENT_STATUS_PENDING
  end

  def successful?
    status == PAYMENT_STATUS_SUCCESS
  end

  def pending?
    status == PAYMENT_STATUS_PENDING
  end

  def failed?
    status == PAYMENT_STATUS_FAILED
  end

  def fully_refunded?
    refunded_amount_cents >= amount_cents
  end

  def transaction_id
    transactions&.last&.transaction_id
  end

  def to_h
    {
      id: payment_id,
      account_id: account_id,
      payment_number: payment_number,
      external_key: payment_external_key,
      amount_cents: amount_cents,
      refunded_amount_cents: refunded_amount_cents,
      currency: currency,
      status: status,
      payment_method_id: payment_method_id,
      transaction_id: transaction_id
    }
  end
end
