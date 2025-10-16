
import * as React from "react";

import { Select } from "$app/components/Select";

import type { Item } from "$app/components/Audience/Customers";
import type { Product } from "$app/components/Audience/Customers";

const ProductSelect = ({
  label,
  products,
  items,
  setItems,
}: {
  label: string;
  products: Product[];
  items: Item[];
  setItems: (items: Item[]) => void;
}) => {
  const uid = React.useId();
  return (
    <fieldset>
      <legend>
        <label htmlFor={uid}>{label}</label>
      </legend>
      <Select
        inputId={uid}
        options={products.flatMap((product) => [
          { id: product.id, label: product.name, type: "product" },
          ...product.variants.map(({ id, name }) => ({
            id: `${product.id} ${id}`,
            label: `${product.name} - ${name}`,
          })),
        ])}
        value={items.flatMap((item) => {
          if (item.type === "product") {
            const product = products.find(({ id }) => id === item.id);
            if (!product) return [];
            return { id: item.id, label: product.name };
          }
          const product = products.find(({ id }) => id === item.productId);
          if (!product) return [];
          const variant = product.variants.find((variant) => variant.id === item.id);
          if (!variant) return [];
          return { id: `${product.id} ${item.id}`, label: `${product.name} - ${variant.name}` };
        })}
        onChange={(items) =>
          setItems(
            items.map((item) => {
              const [productId, variantId] = item.id.split(" ");
              return variantId ? { type: "variant", id: variantId, productId } : { type: "product", id: item.id };
            }),
          )
        }
        isMulti
        isClearable
      />
    </fieldset>
  );
};

export default ProductSelect;
