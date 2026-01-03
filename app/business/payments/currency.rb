# frozen_string_literal: true

module Currency
  # These currencies can be used as account's default currency and to set product prices,
  # along with creating Stripe Connect accounts and making payouts.
  CURRENCY_CHOICES.each do |currency_type, _currency_hash|
    const_set(currency_type.upcase, currency_type.downcase)
  end

  # Cryptocurrencies that can be used as base currency for crypto-native instances.
  # These support different decimal precision and subunit naming conventions.
  CRYPTO_CURRENCIES.each do |currency_type, _currency_hash|
    const_set(currency_type.upcase, currency_type.downcase)
  end

  # Returns the configured instance base currency (defaults to USD for backward compatibility)
  def self.base
    INSTANCE_BASE_CURRENCY
  end

  # Returns true if the instance is configured to use a cryptocurrency as base currency
  def self.crypto_base?
    CRYPTO_CURRENCIES.key?(INSTANCE_BASE_CURRENCY)
  end

  # Returns true if the given currency is a cryptocurrency
  def self.crypto?(currency_type)
    CRYPTO_CURRENCIES.key?(currency_type.to_s.downcase)
  end

  # Returns true if the given currency is a stablecoin (pegged to fiat)
  # Stablecoins have lower volatility and can be treated more like fiat for pricing
  STABLECOINS = %w[usdt usdc dai].freeze
  def self.stablecoin?(currency_type)
    STABLECOINS.include?(currency_type.to_s.downcase)
  end

  # Returns the decimal precision for a cryptocurrency
  # Fiat currencies typically use 2 decimals, crypto varies (6-18)
  def self.decimals_for(currency_type)
    crypto_config = CRYPTO_CURRENCIES[currency_type.to_s.downcase]
    return crypto_config["decimals"] || crypto_config[:decimals] if crypto_config

    # Default to 2 for fiat currencies
    2
  end

  # Returns the subunit to unit conversion factor for a currency
  # For fiat: typically 100 (cents to dollars)
  # For crypto: varies widely (e.g., 100000000 for BTC satoshis)
  def self.subunit_to_unit(currency_type)
    crypto_config = CRYPTO_CURRENCIES[currency_type.to_s.downcase]
    return crypto_config["subunit_to_unit"] || crypto_config[:subunit_to_unit] if crypto_config

    fiat_config = CURRENCY_CHOICES[currency_type.to_s.downcase]
    return 1 if fiat_config && (fiat_config["single_unit"] || fiat_config[:single_unit])

    # Default to 100 for standard fiat currencies
    100
  end

  # Returns true if the currency is considered volatile (non-stablecoin crypto)
  # Volatile currencies may need special handling for pricing (e.g., rate locking)
  def self.volatile?(currency_type)
    crypto?(currency_type) && !stablecoin?(currency_type)
  end

  # Returns the display precision for a currency (how many decimals to show in UI)
  # Stablecoins show 2 decimals like fiat, volatile crypto shows more
  def self.display_decimals_for(currency_type)
    return 2 if stablecoin?(currency_type)
    return 2 unless crypto?(currency_type)

    # For volatile crypto, show up to 8 decimals but cap at the currency's precision
    [decimals_for(currency_type), 8].min
  end

  # Crypto payment method types for detection in purchase flow
  CRYPTO_PAYMENT_METHODS = %w[
    crypto_wallet
    bitcoin
    ethereum
    litecoin
    usdc
    usdt
    dai
    solana
    dogecoin
  ].freeze

  # Returns true if the payment method indicates a crypto payment
  def self.crypto_payment_method?(payment_method)
    return false if payment_method.blank?

    method_lower = payment_method.to_s.downcase
    CRYPTO_PAYMENT_METHODS.include?(method_lower) ||
      method_lower.start_with?("crypto_") ||
      crypto?(method_lower)
  end

  # Returns the crypto currency code from a payment method string
  # e.g., "crypto_btc" -> "btc", "bitcoin" -> "btc"
  PAYMENT_METHOD_TO_CRYPTO = {
    "bitcoin" => "btc",
    "ethereum" => "eth",
    "litecoin" => "ltc",
    "solana" => "sol",
    "dogecoin" => "doge",
  }.freeze

  def self.crypto_currency_from_payment_method(payment_method)
    return nil if payment_method.blank?

    method_lower = payment_method.to_s.downcase

    # Handle "crypto_xxx" format
    if method_lower.start_with?("crypto_")
      currency = method_lower.sub("crypto_", "")
      return currency if crypto?(currency)
    end

    # Handle direct currency codes
    return method_lower if crypto?(method_lower)

    # Handle common names
    PAYMENT_METHOD_TO_CRYPTO[method_lower]
  end

  # Returns true if a purchase should be treated as a crypto purchase
  # based on the product's currency or the payment method used
  def self.crypto_purchase?(product_currency, payment_method = nil)
    crypto?(product_currency) || crypto_payment_method?(payment_method)
  end

  # Crypto refunds are "net" not "gross" - transaction fees are NOT refunded
  # This is because crypto transactions cannot be reversed, only new outbound
  # transactions can be created to return funds
  def self.crypto_refund_amount(original_amount, transaction_fee)
    return 0 if original_amount.to_i <= 0

    refund = original_amount.to_i - transaction_fee.to_i
    refund.positive? ? refund : 0
  end

  # These currencies are only used for creating Stripe Connect accounts and making payouts.
  # These cannot be used as account's default currency or to set product prices.
  # Currency conversion helpers do not support for these currencies.
  THB = "thb"
  BAM = "bam"
  BDT = "bdt"
  BTN = "btn"
  LAK = "lak"
  MZN = "mzn"
  DKK = "dkk"
  HUF = "huf"
  AED = "aed"
  TTD = "ttd"
  AOA = "aoa"
  RON = "ron"
  SEK = "sek"
  MXN = "mxn"
  ARS = "ars"
  NOK = "nok"
  BWP = "bwp"
  PEN = "pen"
  VND = "vnd"
  XCD = "xcd"
  TZS = "tzs"
  NAD = "nad"
  IDR = "idr"
  CRC = "crc"
  RWF = "rwf"
  CLP = "clp"
  PKR = "pkr"
  TRY = "try"
  MAD = "mad"
  RSD = "rsd"
  KES = "kes"
  EGP = "egp"
  COP = "cop"
  SAR = "sar"
  KZT = "kzt"
  MYR = "myr"
  UYU = "uyu"
  MUR = "mur"
  JMD = "jmd"
  OMR = "omr"
  DOP = "dop"
  UZS = "uzs"
  BOB = "bob"
  TND = "tnd"
  NGN = "ngn"
  AZN = "azn"
  JOD = "jod"
  BHD = "bhd"
  ALL = "all"
  MDL = "mdl"
  MKD = "mkd"
  SVC = "svc"
  MGA = "mga"
  PYG = "pyg"
  GHS = "ghs"
  AMD = "amd"
  LKR = "lkr"
  KWD = "kwd"
  QAR = "qar"
  BSD = "bsd"
  ETB = "etb"
  BND = "bnd"
  GYD = "gyd"
  GTQ = "gtq"
  XOF = "xof"
  KHR = "khr"
  MNT = "mnt"
  XAF = "xaf"
  DZD = "dzd"
  MOP = "mop"
end
