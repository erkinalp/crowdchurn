import { ProductNativeType } from "$app/parsers/product";

const NATIVE_TYPE_TO_VARIANT_LABEL: Partial<Record<ProductNativeType, string>> = {
  call: "Duration",
  coffee: "Amount",
  consultancy: "Package",
  fund_cart: "Tier",
  membership: "Tier",
  physical: "Variant",
  print_book: "Edition",
  food: "Variant",
  bread: "Variant",
  literal_coffee: "Blend",
};

export const variantLabel = (type: ProductNativeType): string => NATIVE_TYPE_TO_VARIANT_LABEL[type] || "Version";
