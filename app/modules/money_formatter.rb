# frozen_string_literal: true

module MoneyFormatter
  module_function

  def format(amount, currency_type, opts = {})
    amount ||= 0
    currency_key = currency_type.to_s.downcase.to_sym

    # Get symbol from fiat or crypto currencies
    unless opts[:symbol] == false
      fiat_config = CURRENCY_CHOICES[currency_key]
      crypto_config = CRYPTO_CURRENCIES[currency_key.to_s]
      opts[:symbol] = fiat_config&.dig(:symbol) || crypto_config&.dig("symbol") || crypto_config&.dig(:symbol)
    end

    # For cryptocurrencies, use custom formatting to handle different decimal precisions
    if Currency.crypto?(currency_type)
      format_crypto(amount, currency_type, opts)
    else
      Money.new(amount, currency_type).format(opts)
    end
  end

  # Format cryptocurrency amounts with appropriate decimal precision
  # Crypto amounts are stored in their smallest subunit (satoshis, wei, etc.)
  def format_crypto(amount, currency_type, opts = {})
    currency_key = currency_type.to_s.downcase
    config = CRYPTO_CURRENCIES[currency_key]
    return amount.to_s unless config

    subunit_to_unit = config["subunit_to_unit"] || config[:subunit_to_unit] || 100_000_000
    symbol = opts[:symbol] || config["symbol"] || config[:symbol] || currency_key.upcase

    # Convert from subunits to main units
    main_amount = BigDecimal(amount.to_s) / BigDecimal(subunit_to_unit.to_s)

    # Determine display precision
    display_decimals = Currency.display_decimals_for(currency_type)

    # Format the number
    formatted_number = if opts[:no_cents_if_whole] && main_amount == main_amount.floor
      main_amount.to_i.to_s
    else
      # Use appropriate decimal places, removing trailing zeros
      sprintf("%.#{display_decimals}f", main_amount).sub(/\.?0+$/, "")
    end

    # Apply symbol
    if opts[:symbol] == false
      formatted_number
    else
      "#{symbol}#{formatted_number}"
    end
  end

  # Format crypto amount for display with full precision (useful for receipts/invoices)
  def format_crypto_full_precision(amount, currency_type)
    currency_key = currency_type.to_s.downcase
    config = CRYPTO_CURRENCIES[currency_key]
    return amount.to_s unless config

    subunit_to_unit = config["subunit_to_unit"] || config[:subunit_to_unit] || 100_000_000
    decimals = config["decimals"] || config[:decimals] || 8
    symbol = config["symbol"] || config[:symbol] || currency_key.upcase

    main_amount = BigDecimal(amount.to_s) / BigDecimal(subunit_to_unit.to_s)
    formatted_number = sprintf("%.#{decimals}f", main_amount).sub(/\.?0+$/, "")

    "#{symbol}#{formatted_number}"
  end
end
