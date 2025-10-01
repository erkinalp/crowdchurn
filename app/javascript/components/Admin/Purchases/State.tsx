import React from "react";
import { type Purchase } from "$app/components/Admin/Purchases/Purchase";
import { capitalize } from "lodash";
import AdminPurchasesErrorCode from "$app/components/Admin/Purchases/ErrorCode";

const AdminPurchasesState = ({ purchase }: { purchase: Purchase }) => {
  return (
    <ul className="inline">
      <li>{capitalize(purchase.purchase_state)}</li>
      {purchase.stripe_refunded && <li>(refunded)</li>}
      {purchase.stripe_partially_refunded && <li>(partially refunded)</li>}
      {purchase.chargedback_not_reversed && <li>(chargeback)</li>}
      {purchase.chargeback_reversed && <li>(chargeback reversed)</li>}
      {purchase.error_code && <li><AdminPurchasesErrorCode purchase={purchase} /></li>}
    </ul>
  );
};

export default AdminPurchasesState;
