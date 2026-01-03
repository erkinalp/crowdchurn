# frozen_string_literal: true

Money.locale_backend = :i18n
Money.rounding_mode = BigDecimal::ROUND_HALF_UP
Money.default_currency = "USD"

# technically KRW does have subunits but they are not used anymore
# our currencies.yml assumes KRW to have 100 subunits and that's how we store them in the database
# the gem 'money' however treats KRW as a single unit currency by default
# https://github.com/RubyMoney/money/blob/master/config/currency_iso.json
# so we're performing this override here to have Money treat KRW amounts as 1/100th cents instead of units
# the alternative to this fix would be to update currencies.yml to list KRW as single-unit AND to update the database to divide all KRW prices by 100
Money::Currency.inherit :krw, subunit_to_unit: 100

# The gem 'money' treats HUF as a single unit currency by default
# so we're performing this override here to have Money treat HUF amounts as 1/100th cents instead of units
# because that is what ISO 4217 says and what PayPal expects.
# They're trying to do this migration in the gem too: https://github.com/RubyMoney/money/pull/742
Money::Currency.inherit :huf, subunit_to_unit: 100

# Register cryptocurrency currencies with the Money gem
# These are not ISO 4217 currencies but are used for crypto-native pricing
# Note: We use custom formatting in MoneyFormatter for crypto, but registering
# them here allows Money.new to work with crypto currency codes
CRYPTO_CURRENCY_DEFINITIONS = {
  btc: { priority: 100, iso_code: "BTC", name: "Bitcoin", symbol: "₿", subunit: "Satoshi", subunit_to_unit: 100_000_000, decimal_mark: ".", thousands_separator: "," },
  eth: { priority: 100, iso_code: "ETH", name: "Ethereum", symbol: "Ξ", subunit: "Wei", subunit_to_unit: 1_000_000_000_000_000_000, decimal_mark: ".", thousands_separator: "," },
  ltc: { priority: 100, iso_code: "LTC", name: "Litecoin", symbol: "Ł", subunit: "Litoshi", subunit_to_unit: 100_000_000, decimal_mark: ".", thousands_separator: "," },
  xmr: { priority: 100, iso_code: "XMR", name: "Monero", symbol: "ɱ", subunit: "Piconero", subunit_to_unit: 1_000_000_000_000, decimal_mark: ".", thousands_separator: "," },
  usdt: { priority: 100, iso_code: "USDT", name: "Tether", symbol: "₮", subunit: "Cent", subunit_to_unit: 1_000_000, decimal_mark: ".", thousands_separator: "," },
  usdc: { priority: 100, iso_code: "USDC", name: "USD Coin", symbol: "USDC", subunit: "Cent", subunit_to_unit: 1_000_000, decimal_mark: ".", thousands_separator: "," },
  dai: { priority: 100, iso_code: "DAI", name: "Dai", symbol: "DAI", subunit: "Wei", subunit_to_unit: 1_000_000_000_000_000_000, decimal_mark: ".", thousands_separator: "," },
  sol: { priority: 100, iso_code: "SOL", name: "Solana", symbol: "SOL", subunit: "Lamport", subunit_to_unit: 1_000_000_000, decimal_mark: ".", thousands_separator: "," },
  doge: { priority: 100, iso_code: "DOGE", name: "Dogecoin", symbol: "Ð", subunit: "Koinu", subunit_to_unit: 100_000_000, decimal_mark: ".", thousands_separator: "," },
  matic: { priority: 100, iso_code: "MATIC", name: "Polygon", symbol: "MATIC", subunit: "Wei", subunit_to_unit: 1_000_000_000_000_000_000, decimal_mark: ".", thousands_separator: "," },
  avax: { priority: 100, iso_code: "AVAX", name: "Avalanche", symbol: "AVAX", subunit: "Wei", subunit_to_unit: 1_000_000_000_000_000_000, decimal_mark: ".", thousands_separator: "," },
  dot: { priority: 100, iso_code: "DOT", name: "Polkadot", symbol: "DOT", subunit: "Planck", subunit_to_unit: 10_000_000_000, decimal_mark: ".", thousands_separator: "," },
  ada: { priority: 100, iso_code: "ADA", name: "Cardano", symbol: "ADA", subunit: "Lovelace", subunit_to_unit: 1_000_000, decimal_mark: ".", thousands_separator: "," },
  bnb: { priority: 100, iso_code: "BNB", name: "BNB", symbol: "BNB", subunit: "Jager", subunit_to_unit: 1_000_000_000_000_000_000, decimal_mark: ".", thousands_separator: "," },
  xrp: { priority: 100, iso_code: "XRP", name: "Ripple", symbol: "XRP", subunit: "Drop", subunit_to_unit: 1_000_000, decimal_mark: ".", thousands_separator: "," },
  trx: { priority: 100, iso_code: "TRX", name: "Tron", symbol: "TRX", subunit: "Sun", subunit_to_unit: 1_000_000, decimal_mark: ".", thousands_separator: "," },
}.freeze

CRYPTO_CURRENCY_DEFINITIONS.each do |code, definition|
  Money::Currency.register(definition)
end
