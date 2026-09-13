# Configurable Base Currency

This document describes how to configure the instance base currency for international deployments and cryptocurrency-native instances.

## Overview

By default, CrowdChurn uses USD as the base currency for all internal calculations, exchange rate conversions, and price storage. This can be changed at the instance level to support international deployments or cryptocurrency-native platforms.

## Configuration

### Environment Variables

Set the following environment variables to configure the base currency:

**INSTANCE_BASE_CURRENCY** (default: "usd")

The base currency used for internal calculations and price storage. This can be any supported fiat currency code (e.g., "eur", "gbp", "jpy") or cryptocurrency code (e.g., "btc", "eth", "usdt").

```bash
# Example: Use Euro as base currency
INSTANCE_BASE_CURRENCY=eur

# Example: Use Bitcoin as base currency
INSTANCE_BASE_CURRENCY=btc
```

**CRYPTO_EXCHANGE_RATE_SOURCE** (optional)

URL for fetching cryptocurrency exchange rates. Required if using a cryptocurrency as the base currency.

```bash
# Example: Custom crypto exchange rate API
CRYPTO_EXCHANGE_RATE_SOURCE=https://api.example.com/crypto-rates.json
```

The API should return JSON in the following format:
```json
{
  "rates": {
    "BTC": 0.000025,
    "ETH": 0.00035,
    "USDT": 1.0
  }
}
```

## Supported Currencies

### Fiat Currencies

All currencies defined in `config/currencies.json` are supported as base currencies:
- USD (US Dollar) - default
- EUR (Euro)
- GBP (British Pound)
- JPY (Japanese Yen)
- And many more...

### Cryptocurrencies

The following cryptocurrencies are supported as base currencies:
- BTC (Bitcoin) - 8 decimal places, subunit: satoshi
- ETH (Ethereum) - 18 decimal places, subunit: wei
- LTC (Litecoin) - 8 decimal places, subunit: litoshi
- XMR (Monero) - 12 decimal places, subunit: piconero
- USDT (Tether) - 6 decimal places
- USDC (USD Coin) - 6 decimal places
- DAI (Dai Stablecoin) - 18 decimal places

## Backward Compatibility

Existing instances that do not set `INSTANCE_BASE_CURRENCY` will continue to use USD as the base currency. All existing method names (e.g., `get_usd_cents`, `usd_cents_to_currency`) remain available as aliases to the new currency-agnostic methods.

## API Reference

### CurrencyHelper Methods

**instance_base_currency**
Returns the configured base currency code.

**get_base_currency_units(currency_type, quantity, rate: nil)**
Converts an amount from the display currency to the base currency units.

**base_currency_to_display_currency(currency_type, quantity, rate = nil)**
Converts an amount from base currency units to the display currency.

**is_crypto_currency?(currency_type)**
Returns true if the currency type is a cryptocurrency.

**get_crypto_currency_config(currency_type)**
Returns the configuration hash for a cryptocurrency.

### Currency Module Methods

**Currency.base**
Returns the configured instance base currency.

**Currency.crypto_base?**
Returns true if the instance is configured to use a cryptocurrency as base currency.

## Migration Notes

When changing the base currency for an existing instance:

1. All stored prices in `price_cents` columns are in base currency units
2. Exchange rates are stored relative to the base currency
3. Historical data will need to be recalculated if changing base currency on an existing instance
4. It is recommended to only set the base currency during initial instance setup

## Exchange Rate Updates

The `UpdateCurrenciesWorker` Sidekiq job handles exchange rate updates:
- Fiat rates are fetched from OpenExchangeRates API
- If the base currency is not USD, rates are automatically converted
- Crypto rates are fetched from the configured `CRYPTO_EXCHANGE_RATE_SOURCE` if set
