import * as React from "react";

import { CurrencyCode } from "$app/utils/currency";

import { PriceInput } from "$app/components/PriceInput";
import { useProductEditContext, AvailableCurrency } from "$app/components/ProductEdit/state";

export const GrossPriceEditor = ({
  priceCents,
  setPriceCents,
  currencyType,
  currencyCodeSelector,
}: {
  priceCents: number;
  setPriceCents: (priceCents: number) => void;
  currencyType: CurrencyCode;
  currencyCodeSelector?: { options: CurrencyCode[]; onChange: (currencyCode: CurrencyCode) => void };
}) => {
  const { availableCurrencies } = useProductEditContext();

  const getEquivalentPrices = (): { currency: string; symbol: string; amount: string }[] => {
    if (priceCents === 0) return [];

    const baseCurrency = availableCurrencies.find(
      (c: AvailableCurrency) => c.code.toLowerCase() === currencyType.toLowerCase(),
    );
    if (!baseCurrency) return [];

    return availableCurrencies
      .filter((c: AvailableCurrency) => c.code.toLowerCase() !== currencyType.toLowerCase())
      .slice(0, 5)
      .map((c: AvailableCurrency) => ({
        currency: c.code.toUpperCase(),
        symbol: c.symbol,
        amount: (priceCents / 100).toFixed(2),
      }));
  };

  const equivalentPrices = getEquivalentPrices();

  return (
    <fieldset>
      <legend>
        Price <span className="text-muted">(tax-inclusive)</span>
      </legend>
      <PriceInput
        currencyCode={currencyType}
        currencyCodeSelector={currencyCodeSelector}
        cents={priceCents}
        onChange={(cents) => setPriceCents(cents ?? 0)}
        ariaLabel="Tax-inclusive price"
      />
      <p className="mt-2 text-sm text-muted">This price will be charged as the same gross amount in all currencies.</p>
      {equivalentPrices.length > 0 && (
        <div className="mt-3">
          <p className="text-sm text-muted">Equivalent in other currencies (same value):</p>
          <div className="mt-1 flex flex-wrap gap-2 text-sm text-muted">
            {equivalentPrices.map((ep) => (
              <span key={ep.currency} className="rounded bg-gray-100 px-2 py-1">
                {ep.symbol}
                {ep.amount} {ep.currency}
              </span>
            ))}
          </div>
        </div>
      )}
    </fieldset>
  );
};
