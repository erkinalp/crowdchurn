# frozen_string_literal: true

class UpdateCurrenciesWorker
  include Sidekiq::Job
  include CurrencyHelper
  sidekiq_options retry: 5, queue: :default

  def perform
    update_fiat_rates
    update_crypto_rates if CRYPTO_EXCHANGE_RATE_SOURCE.present?
  end

  private
    def update_fiat_rates
      rates = JSON.parse(URI.open(CURRENCY_SOURCE).read)["rates"]
      base_currency = INSTANCE_BASE_CURRENCY.upcase

      if base_currency != "USD"
        base_rate = rates[base_currency]
        if base_rate && base_rate.to_f > 0
          rates = rates.transform_values { |rate| rate.to_f / base_rate.to_f }
          rates[base_currency] = 1.0
        end
      end

      rates.each do |currency, rate|
        currency_namespace.set(currency.to_s, rate)
      end
    end

    def update_crypto_rates
      return if CRYPTO_EXCHANGE_RATE_SOURCE.blank?

      begin
        crypto_rates = JSON.parse(URI.open(CRYPTO_EXCHANGE_RATE_SOURCE).read)["rates"]
        crypto_rates&.each do |currency, rate|
          currency_namespace.set(currency.to_s.upcase, rate)
        end
      rescue StandardError => e
        Rails.logger.error("Failed to update crypto rates: #{e.message}")
      end
    end
end
