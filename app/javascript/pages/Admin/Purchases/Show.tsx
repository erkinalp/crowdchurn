import { usePage } from "@inertiajs/react";
import React from "react";

import Product, { type Product as ProductType } from "$app/components/Admin/Products/Product";
import PurchaseDetails, { type Purchase as PurchaseType } from "$app/components/Admin/Purchases/PurchaseDetails";
import User, { type User as UserType } from "$app/components/Admin/Users/User";

type AdminPurchasesShowProps = {
  purchase: PurchaseType;
  product: ProductType;
  user: UserType;
};

const AdminPurchasesShow = () => {
  const { purchase, product, user } = usePage<AdminPurchasesShowProps>().props;

  return (
    <div className="paragraphs">
      <PurchaseDetails purchase={purchase} />
      <Product user={user} product={product} isAffiliateUser={false} />
      <User user={user} isAffiliateUser={false} />
    </div>
  );
};

export default AdminPurchasesShow;
