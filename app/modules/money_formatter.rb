# frozen_string_literal: true

module MoneyFormatter
  module_function

  # Soft-fail unknown codes (log + ISO) so one corrupt sale cannot 500 a Sales list.
  # Do not fall back to USD. Hard-fail callers should build Money::Currency themselves.
  def format(amount, currency_type, opts = {})
    amount ||= 0
    opts = opts.dup
    return format_crypto(amount, currency_type, opts) if Currency.crypto?(currency_type)

    with_symbol = opts[:symbol] != false
    currency = find_currency(currency_type)
    unless currency
      soft_fail_unknown_currency(currency_type)
      number = Money.new(amount, "usd").format(opts.merge(symbol: false))
      iso = iso_code_for(currency_type)
      return with_symbol && iso.present? ? "#{number} #{iso}" : number
    end

    opts[:symbol] = pricing_or_registry_symbol(currency_type, currency) if with_symbol
    Money.new(amount, currency).format(opts)
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
      main_amount.round(display_decimals).to_s("F").sub(/\.?0+$/, "")
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
    formatted_number = main_amount.round(decimals).to_s("F").sub(/\.?0+$/, "")

    "#{symbol}#{formatted_number}"
  end

  def symbol_for(currency_type)
    if Currency.crypto?(currency_type)
      config = CRYPTO_CURRENCIES.fetch(currency_type.to_s.downcase)
      return config["symbol"] || config[:symbol] || iso_code_for(currency_type)
    end

    currency = find_currency(currency_type)
    unless currency
      soft_fail_unknown_currency(currency_type)
      return iso_code_for(currency_type)
    end

    pricing_or_registry_symbol(currency_type, currency)
  end

  def find_currency(currency_type)
    code = currency_type.to_s.downcase
    return if code.blank?

    Money::Currency.new(code)
  rescue Money::Currency::UnknownCurrency
    nil
  end
  private_class_method :find_currency

  def pricing_or_registry_symbol(currency_type, currency)
    CURRENCY_CHOICES.dig(currency_type.to_s.downcase, :symbol) || currency.symbol
  end
  private_class_method :pricing_or_registry_symbol

  def iso_code_for(currency_type)
    currency_type.to_s.upcase.presence || ""
  end
  private_class_method :iso_code_for

  def soft_fail_unknown_currency(currency_type)
    Rails.logger.warn(
      "MoneyFormatter: unknown currency #{currency_type.inspect}; displaying ISO code instead of raising"
    )
  end
  private_class_method :soft_fail_unknown_currency
end
