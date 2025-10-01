import React from "react";
import { usePage } from "@inertiajs/react";
import AdminPurchases from "$app/components/Admin/Purchases";
import { type Purchase } from "$app/components/Admin/Purchases/Purchase";
import { type Pagination } from "$app/hooks/useLazyFetch";
import AdminEmptyState from "$app/components/Admin/EmptyState";

type Props = {
  purchases: Purchase[];
  pagination: Pagination;
  query: string;
  product_title_query: string;
  purchase_status: string;
};

const AdminSearchPurchases = () => {
  const { purchases, pagination, query, product_title_query, purchase_status } = usePage().props as unknown as Props;

  if (purchases.length === 0 && pagination.page === 1) {
    return <AdminEmptyState message="No purchases found." />;
  }

  return (
    <AdminPurchases
      purchases={purchases}
      pagination={pagination}
      query={query}
      product_title_query={product_title_query}
      purchase_status={purchase_status}
    />
  );
};

export default AdminSearchPurchases;
