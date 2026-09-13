# frozen_string_literal: true

# Represents a Kill Bill setup intent for future charges
# Kill Bill doesn't have a separate setup intent concept like Stripe,
# so this wraps a payment method for API compatibility
class KillbillSetupIntent
  attr_reader :payment_method

  def initialize(payment_method)
    @payment_method = payment_method
  end

  def id
    payment_method&.payment_method_id
  end

  def status
    payment_method.present? ? "succeeded" : "failed"
  end

  def succeeded?
    payment_method.present?
  end

  def requires_action?
    false
  end

  def canceled?
    false
  end
end
