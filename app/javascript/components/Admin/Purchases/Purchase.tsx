import React from "react";
import { Link } from "@inertiajs/react";
import AdminPurchasesState from "$app/components/Admin/Purchases/State";

export type Purchase = {
  id: number;
  email: string;
  formatted_display_price: string;
  formatted_gumroad_tax_amount: string;
  link: {
    id: number;
    long_url: string;
    name: string;
  };
  variants_list: string;
  purchase_states: string[];
  purchase_refund_policy: {
    title: string;
  };
  seller: {
    email: string;
  };
  failed: boolean;
  error_code: string;
  formatted_error_code: string;
  purchase_state: string;
  stripe_refunded: boolean;
  stripe_partially_refunded: boolean;
  chargedback_not_reversed: boolean;
  chargeback_reversed: boolean;
  created_at: string;
};

type Props = {
  purchase: Purchase;
};

const AdminPurchasesPurchase = ({ purchase }: Props) => {
  return (
    <tr>
      <td data-label="Purchase">
        <Link href={Routes.admin_purchase_path(purchase.id)}>{purchase.formatted_display_price}</Link>
        {purchase.formatted_gumroad_tax_amount ? ` + ${purchase.formatted_gumroad_tax_amount} VAT` : null}
        <Link href={Routes.admin_product_url(purchase.link.id)}>{purchase.link.name}</Link>
        {purchase.variants_list}
        <Link href={purchase.link.long_url} target="_blank" className="no-underline">
          <span className="icon icon-arrow-up-right-square"></span>
        </Link>
        <AdminPurchasesState purchase={purchase} />
        <div className="text-sm">
          <ul className="inline">
            {purchase.purchase_refund_policy.title ? <li>Refund policy: {purchase.purchase_refund_policy.title}</li> : null}
            <li>Seller: {purchase.seller.email}</li>
          </ul>
        </div>
      </td>
      <td data-label="By">
        <Link href={Routes.admin_search_purchases_path({ query: purchase.email })}>{purchase.email}</Link>
        <small>{purchase.created_at}</small>
      </td>
    </tr>
  );
};

export default AdminPurchasesPurchase;
