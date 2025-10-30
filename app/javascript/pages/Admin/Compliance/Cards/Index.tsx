import { usePage } from "@inertiajs/react";
import React from "react";

import { type Pagination } from "$app/hooks/useLazyFetch";

import AdminPurchases from "$app/components/Admin/Purchases";
import { type Purchase } from "$app/components/Admin/Purchases/PurchaseDetails";

type PageProps = {
  purchases: Purchase[];
  query: string;
  product_title_query: string;
  purchase_status: string;
  pagination: Pagination;
};

const AdminComplianceCards = () => {
  const { purchases, query, product_title_query, purchase_status, pagination } = usePage<PageProps>().props;
  return (
    <div className="space-y-4">
      <AdminPurchases
        purchases={purchases}
        query={query}
        product_title_query={product_title_query}
        purchase_status={purchase_status}
        pagination={pagination}
        endpoint={Routes.admin_cards_path}
      />
    </div>
  );
};

export default AdminComplianceCards;
