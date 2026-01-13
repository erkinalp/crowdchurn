import * as React from "react";

import { PricingMode, useProductEditContext } from "$app/components/ProductEdit/state";

const PRICING_MODES: { id: PricingMode; label: string; description: string }[] = [
  {
    id: "legacy",
    label: "Single currency (legacy)",
    description: "Set one price in your base currency. Other currencies are converted dynamically and taxes are applied on top.",
  },
  {
    id: "gross",
    label: "Tax-inclusive (gross)",
    description: "Set one tax-inclusive price. The same value is charged in all currencies.",
  },
  {
    id: "multi_currency",
    label: "Multi-currency",
    description: "Set explicit prices for each currency you want to support.",
  },
];

export const PricingModeSelector = () => {
  const { product, updateProduct } = useProductEditContext();

  return (
    <fieldset>
      <legend>Pricing mode</legend>
      <div className="flex flex-col gap-2">
        {PRICING_MODES.map((mode) => (
          <label key={mode.id} className="flex items-start gap-2">
            <input
              type="radio"
              name="pricing_mode"
              value={mode.id}
              checked={product.pricing_mode === mode.id}
              onChange={() => updateProduct({ pricing_mode: mode.id })}
              className="mt-1"
            />
            <div>
              <span className="font-medium">{mode.label}</span>
              <p className="text-sm text-muted">{mode.description}</p>
            </div>
          </label>
        ))}
      </div>
    </fieldset>
  );
};
