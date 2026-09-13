import { Trash } from "@boxicons/react";
import * as React from "react";

import {
  findCryptocurrencyByCode,
  formatPriceCentsWithCurrencySymbol,
  isCryptocurrency,
  isCurrencyCode,
} from "$app/utils/currency";

import { Button } from "$app/components/Button";
import { PriceInput } from "$app/components/PriceInput";
import {
  CurrencyPrice,
  AvailableCurrency,
  AvailableCryptocurrency,
  useProductEditContext,
} from "$app/components/ProductEdit/state";
import { TypeSafeOptionSelect } from "$app/components/TypeSafeOptionSelect";
import { Input } from "$app/components/ui/Input";

type CurrencyOption = {
  code: string;
  symbol: string;
  displayFormat: string;
  minPrice: number;
  isCrypto: boolean;
  decimals?: number;
};

export const MultiCurrencyPriceEditor = () => {
  const { product, updateProduct, availableCurrencies, availableCryptocurrencies } = useProductEditContext();
  const currencyPrices = product.currency_prices;

  const allCurrencyOptions: CurrencyOption[] = React.useMemo(() => {
    const fiatOptions: CurrencyOption[] = availableCurrencies.map((c: AvailableCurrency) => ({
      code: c.code,
      symbol: c.symbol,
      displayFormat: c.display_format,
      minPrice: c.min_price,
      isCrypto: false,
    }));

    const cryptoOptions: CurrencyOption[] = availableCryptocurrencies.map((c: AvailableCryptocurrency) => ({
      code: c.code,
      symbol: c.symbol,
      displayFormat: c.display_format,
      minPrice: c.min_price,
      isCrypto: true,
      decimals: c.decimals,
    }));

    return [...fiatOptions, ...cryptoOptions];
  }, [availableCurrencies, availableCryptocurrencies]);

  const usedCurrencies = new Set(currencyPrices.map((p) => p.currency.toLowerCase()));
  const availableToAdd = allCurrencyOptions.filter((c) => !usedCurrencies.has(c.code.toLowerCase()));

  const addCurrencyPrice = (currencyCode: string) => {
    const newPrice: CurrencyPrice = {
      id: null,
      currency: currencyCode,
      price_cents: 0,
      recurrence: null,
      newlyAdded: true,
    };
    updateProduct({
      currency_prices: [...currencyPrices, newPrice],
    });
  };

  const updateCurrencyPrice = (index: number, priceCents: number | null) => {
    const updated = currencyPrices.map((price, i) =>
      i === index ? { ...price, price_cents: priceCents ?? 0 } : price,
    );
    updateProduct({ currency_prices: updated });
  };

  const removeCurrencyPrice = (index: number) => {
    const updated = currencyPrices.filter((_, i) => i !== index);
    updateProduct({ currency_prices: updated });
  };

  const getCurrencyOption = (code: string): CurrencyOption | undefined =>
    allCurrencyOptions.find((c) => c.code.toLowerCase() === code.toLowerCase());

  const getMinPriceDisplay = (currencyCode: string): string => {
    const option = getCurrencyOption(currencyCode);
    if (!option) return "";
    const minAmount = option.minPrice;
    const code = currencyCode.toLowerCase();
    if (isCurrencyCode(code)) {
      return `Min: ${formatPriceCentsWithCurrencySymbol(code, minAmount, { symbolFormat: "long" })}`;
    }
    return `Min: ${minAmount} ${isCryptocurrency(code) ? findCryptocurrencyByCode(code).subunit : "minor units"}`;
  };

  const validatePrice = (currencyCode: string, priceAmount: number): boolean => {
    const option = getCurrencyOption(currencyCode);
    if (!option) return true;
    return priceAmount >= option.minPrice;
  };

  return (
    <div className="flex flex-col gap-4">
      <fieldset>
        <legend>Currency prices</legend>
        <div className="flex flex-col gap-3">
          {currencyPrices.map((price, index) => {
            const isValid = validatePrice(price.currency, price.price_cents);
            const currencyCode = price.currency.toLowerCase();

            return (
              <div key={price.id || `new-${index}`} className="flex items-center gap-2">
                <div className="flex-1">
                  {isCurrencyCode(currencyCode) ? (
                    <PriceInput
                      currencyCode={currencyCode}
                      cents={price.price_cents}
                      onChange={(cents) => updateCurrencyPrice(index, cents)}
                      hasError={!isValid}
                      ariaLabel={`Price in ${price.currency.toUpperCase()}`}
                    />
                  ) : (
                    <label>
                      {price.currency.toUpperCase()} (
                      {isCryptocurrency(currencyCode) ? findCryptocurrencyByCode(currencyCode).subunit : "minor units"})
                      <Input
                        type="number"
                        min={0}
                        max={Number.MAX_SAFE_INTEGER}
                        step={1}
                        value={price.price_cents}
                        aria-invalid={!isValid}
                        onChange={(event) => {
                          const amount = Number(event.target.value);
                          if (Number.isSafeInteger(amount) && amount >= 0) updateCurrencyPrice(index, amount);
                        }}
                      />
                    </label>
                  )}
                  {!isValid && <p className="mt-1 text-sm text-danger">{getMinPriceDisplay(price.currency)}</p>}
                </div>
                <Button
                  type="button"
                  size="sm"
                  onClick={() => removeCurrencyPrice(index)}
                  aria-label={`Remove ${price.currency.toUpperCase()} price`}
                >
                  <Trash className="size-5" />
                </Button>
              </div>
            );
          })}

          {availableToAdd.length > 0 && (
            <div className="mt-2">
              <label htmlFor="add-currency">Add currency</label>
              <TypeSafeOptionSelect
                id="add-currency"
                value=""
                onChange={(code) => {
                  if (code) addCurrencyPrice(code);
                }}
                options={[
                  { id: "", label: "Select currency..." },
                  ...availableToAdd.map((c) => ({
                    id: c.code,
                    label: `${c.displayFormat}${c.isCrypto ? " (crypto)" : ""}`,
                  })),
                ]}
              />
            </div>
          )}
        </div>
      </fieldset>
    </div>
  );
};
