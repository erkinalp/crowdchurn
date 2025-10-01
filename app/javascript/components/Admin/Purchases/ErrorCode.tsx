import React from "react";
import { type Purchase } from "$app/components/Admin/Purchases/Purchase";
import { Link } from "@inertiajs/react";
import { useLazyFetch } from "$app/hooks/useLazyFetch";
import { cast } from "ts-safe-cast";
import Loading from "$app/components/Admin/Loading";

const AdminPurchasesErrorCode = ({ purchase }: { purchase: Purchase }) => {
  if (!purchase.failed) {
    return null;
  }

  const {
    data: past_chargebacked_purchases,
    isLoading,
    fetchData: fetchPastChargebackedPurchases,
  } = useLazyFetch<Purchase[]>(
    [],
    {
      url: Routes.admin_search_purchase_past_chargebacked_purchases_path(purchase.id),
      responseParser: (data) => cast<Purchase[]>(data.purchases),
    },
  );

  React.useEffect(() => {
    fetchPastChargebackedPurchases();
  }, []);

  if (isLoading) {
    return <Loading />;
  }

  if (past_chargebacked_purchases.length > 0) {
    return (
      <Link href={Routes.admin_purchase_path(past_chargebacked_purchases[0]?.id ?? 0)}>
        {purchase.formatted_error_code}
      </Link>
    );
  }

  return <li>{purchase.formatted_error_code}</li>;
};

export default AdminPurchasesErrorCode;
