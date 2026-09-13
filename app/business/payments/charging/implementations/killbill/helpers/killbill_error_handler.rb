# frozen_string_literal: true

module KillbillErrorHandler
  private
    def with_killbill_error_handler
      yield
    rescue KillBillClient::API::Unauthorized => e
      raise ChargeProcessorInvalidRequestError.new(
        "Kill Bill authentication failed: #{e.message}",
        original_error: e
      )
    rescue KillBillClient::API::NotFound => e
      raise ChargeProcessorInvalidRequestError.new(
        "Kill Bill resource not found: #{e.message}",
        original_error: e
      )
    rescue KillBillClient::API::BadRequest => e
      handle_bad_request_error(e)
    rescue KillBillClient::API::InternalServerError, KillBillClient::API::ServiceUnavailable => e
      raise ChargeProcessorUnavailableError.new(
        "Kill Bill service unavailable: #{e.message}",
        original_error: e
      )
    rescue KillBillClient::API::ResponseError => e
      raise ChargeProcessorErrorRateLimit.new(original_error: e) if e.code == 429

      raise ChargeProcessorErrorGeneric.new(e.code, original_error: e)
    rescue KillBillClient::Error => e
      raise ChargeProcessorErrorGeneric.new("killbill_error", original_error: e)
    rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout, Net::ReadTimeout => e
      raise ChargeProcessorUnavailableError.new(
        "Kill Bill connection error: #{e.message}",
        original_error: e
      )
    rescue StandardError => e
      # Log unexpected errors but don't expose internal details
      Rails.logger.error("Unexpected Kill Bill error: #{e.class} - #{e.message}")
      raise ChargeProcessorErrorGeneric.new("unexpected_error", original_error: e)
    end

    def handle_bad_request_error(error)
      message = error.message.to_s.downcase

      if message.include?("insufficient funds") || message.include?("nsf")
        raise ChargeProcessorInsufficientFundsError.new(original_error: error)
      elsif message.include?("card declined") || message.include?("do not honor")
        raise ChargeProcessorCardError.new(
          "card_declined",
          error.message,
          original_error: error
        )
      elsif message.include?("invalid card") || message.include?("expired card")
        raise ChargeProcessorCardError.new(
          "invalid_card",
          error.message,
          original_error: error
        )
      elsif message.include?("already been refunded")
        raise ChargeProcessorAlreadyRefundedError.new(
          "Kill Bill charge was already refunded: #{error.message}",
          original_error: error
        )
      elsif message.include?("payment method not supported")
        raise ChargeProcessorUnsupportedPaymentTypeError.new(
          "unsupported_payment_type",
          error.message,
          original_error: error
        )
      elsif message.include?("account restricted") || message.include?("account suspended")
        raise ChargeProcessorPayeeAccountRestrictedError.new(original_error: error)
      elsif message.include?("out of credits") || message.include?("credit limit")
        raise ChargeProcessorInsufficientFundsError.new(
          "API credit limit reached: #{error.message}",
          original_error: error
        )
      else
        raise ChargeProcessorInvalidRequestError.new(original_error: error)
      end
    end
end
