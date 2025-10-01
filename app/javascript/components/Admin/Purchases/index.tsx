
import React from "react";
import AdminPurchasesFilterForm from "$app/components/Admin/Purchases/FilterForm";
import AdminPurchasesPurchase, { type Purchase } from "$app/components/Admin/Purchases/Purchase";
import { type Pagination } from "$app/hooks/useLazyFetch";
import { WhenVisible } from "@inertiajs/react";
import Loading from "$app/components/Admin/Loading";

type Props = {
  purchases: Purchase[];
  pagination: Pagination;
  query: string;
  product_title_query: string;
  purchase_status: string;
};

const AdminPurchases = ({
  purchases,
  pagination,
  query,
  product_title_query,
  purchase_status,
}: Props) => {
  const RenderNextPurchasesWhenVisible = () => {
    const purchasesLengthFromCurrentPage = purchases.length / pagination.page;
    if (purchasesLengthFromCurrentPage >= pagination.limit) {
      const params = {
        data: { page: pagination.page + 1 },
        only: ["purchases", "pagination"],
        preserveScroll: true
      }
      return <WhenVisible params={params} fallback={<Loading />} children />;
    }
  };

  return (
    <div className="paragraphs">
      <AdminPurchasesFilterForm query={query} product_title_query={product_title_query} purchase_status={purchase_status} />

      <table>
        <thead>
          <tr>
            <th>Purchase</th>
            <th>By</th>
          </tr>
        </thead>
        <tbody>
          {purchases.map((purchase) => (
            <AdminPurchasesPurchase key={purchase.id} purchase={purchase} />
          ))}

          <RenderNextPurchasesWhenVisible />
        </tbody>
      </table>
    </div>
  );
};

export default AdminPurchases;

//  <%= paginate @purchases, views_prefix: "admin" %>

