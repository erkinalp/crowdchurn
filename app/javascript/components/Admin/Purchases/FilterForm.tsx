import React from "react";
import { Form, Link } from "@inertiajs/react";

type Props = {
  query: string;
  product_title_query: string;
  purchase_status: string;
};

const AdminPurchasesFilterForm = ({
  query,
  product_title_query,
  purchase_status,
}: Props) => {
  return (
    <Form action={Routes.admin_search_purchases_path()} method="get" className="input-with-button mb-4">
      <input type="hidden" name="query" value={query} />
      <div className="input">
        <input type="text" name="product_title_query" placeholder="Filter by product title" value={product_title_query} />
      </div>
      <select name="purchase_status">
        <option value="" selected={purchase_status === ""}>Any status</option>
        <option value="chargeback" selected={purchase_status === "chargeback"}>Chargeback</option>
        <option value="refunded" selected={purchase_status === "refunded"}>Refunded</option>
        <option value="failed" selected={purchase_status === "failed"}>Failed</option>
      </select>
      <button type="submit" className="button primary">
        <span className="icon icon-solid-search"></span>
      </button>
      {product_title_query || purchase_status && <Link href={Routes.admin_search_purchases_path({ query })} className="button secondary">Clear</Link>}
    </Form>
  );
};

export default AdminPurchasesFilterForm;
