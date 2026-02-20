import * as React from "react";

import { CurrencyCode, formatPriceCentsWithCurrencySymbol } from "$app/utils/currency";
import { request, ResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Icon } from "$app/components/Icons";
import { Layout } from "$app/components/ProductEdit/Layout";
import { showAlert } from "$app/components/server-components/Alert";

type FundCartItem = {
  id: string;
  product_id: string;
  product_name: string;
  product_price_cents: number;
  product_native_type: string;
  state: string;
  purchased_at: string | null;
  created_at: string;
};

type FundCartData = {
  items: FundCartItem[];
  balance_subunits: number;
  currency: string;
};

export const FundCartItemsPanel = ({
  fundCartId,
  currencyCode,
}: {
  fundCartId: string;
  currencyCode: CurrencyCode;
}) => {
  const [data, setData] = React.useState<FundCartData | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [productInput, setProductInput] = React.useState("");
  const [addError, setAddError] = React.useState<string | null>(null);
  const [adding, setAdding] = React.useState(false);
  const [removingIds, setRemovingIds] = React.useState<Set<string>>(new Set());

  const fetchItems = React.useCallback(async () => {
    try {
      const resp = await request({
        method: "GET",
        accept: "json",
        url: `/api/internal/fund_carts/${fundCartId}/items`,
      });
      const json: FundCartData = await resp.json();
      setData(json);
    } catch {
      showAlert("Failed to load fund cart items.", "error");
    } finally {
      setLoading(false);
    }
  }, [fundCartId]);

  React.useEffect(() => {
    void fetchItems();
  }, [fetchItems]);

  const handleAdd = async () => {
    setAddError(null);
    const trimmed = productInput.trim();
    if (!trimmed) return;

    setAdding(true);
    try {
      const resp = await request({
        method: "POST",
        accept: "json",
        url: `/api/internal/fund_carts/${fundCartId}/items`,
        data: { product_id: trimmed },
      });
      const json = await resp.json();
      if (!resp.ok) {
        setAddError(json.error || "Failed to add item.");
      } else {
        setProductInput("");
        void fetchItems();
      }
    } catch (e) {
      if (e instanceof ResponseError) {
        setAddError(e.message);
      } else {
        setAddError("Failed to add item.");
      }
    } finally {
      setAdding(false);
    }
  };

  const handleRemove = async (itemId: string) => {
    setRemovingIds((prev) => new Set(prev).add(itemId));
    try {
      const resp = await request({
        method: "DELETE",
        accept: "json",
        url: `/api/internal/fund_carts/${fundCartId}/items/${itemId}`,
      });
      if (resp.ok) {
        void fetchItems();
      } else {
        const json = await resp.json();
        showAlert(json.error || "Failed to remove item.", "error");
      }
    } catch {
      showAlert("Failed to remove item.", "error");
    } finally {
      setRemovingIds((prev) => {
        const next = new Set(prev);
        next.delete(itemId);
        return next;
      });
    }
  };

  const pendingItems = data?.items.filter((i) => i.state === "pending") ?? [];
  const purchasedItems = data?.items.filter((i) => i.state === "purchased") ?? [];

  const formatPrice = (cents: number) =>
    formatPriceCentsWithCurrencySymbol(currencyCode, cents, { symbolFormat: "short" });

  if (loading) {
    return (
      <Layout>
        <div className="flex-1 p-8 text-center">Loading fund cart...</div>
      </Layout>
    );
  }

  return (
    <Layout>
      <div className="squished">
        <section className="p-4! md:p-8!">
          <h2>Fund Balance</h2>
          <p className="text-lg font-semibold">{data ? formatPrice(data.balance_subunits) : "—"}</p>
        </section>

        <section className="p-4! md:p-8!">
          <h2>Add Item</h2>
          <div className="flex gap-2">
            <input
              type="text"
              className="flex-1"
              placeholder="Product ID or permalink"
              value={productInput}
              onChange={(e) => {
                setProductInput(e.target.value);
                setAddError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  void handleAdd();
                }
              }}
            />
            <Button color="primary" disabled={adding || !productInput.trim()} onClick={() => void handleAdd()}>
              {adding ? "Adding..." : "Add"}
            </Button>
          </div>
          {addError ? <p className="mt-2 text-sm text-red-500">{addError}</p> : null}
        </section>

        <section className="p-4! md:p-8!">
          <h2>Pending Items ({pendingItems.length})</h2>
          {pendingItems.length === 0 ? (
            <p className="text-muted">No pending items.</p>
          ) : (
            <table className="w-full">
              <thead>
                <tr>
                  <th className="text-left">Product</th>
                  <th className="text-right">Price</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {pendingItems.map((item) => (
                  <tr key={item.id}>
                    <td>{item.product_name}</td>
                    <td className="text-right">{formatPrice(item.product_price_cents)}</td>
                    <td className="text-right">
                      <Button
                        color="danger"
                        disabled={removingIds.has(item.id)}
                        onClick={() => void handleRemove(item.id)}
                      >
                        <Icon name="trash2" />
                      </Button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>

        <section className="p-4! md:p-8!">
          <h2>Purchased Items ({purchasedItems.length})</h2>
          {purchasedItems.length === 0 ? (
            <p className="text-muted">No purchased items yet.</p>
          ) : (
            <table className="w-full">
              <thead>
                <tr>
                  <th className="text-left">Product</th>
                  <th className="text-right">Price</th>
                  <th className="text-right">Purchased</th>
                </tr>
              </thead>
              <tbody>
                {purchasedItems.map((item) => (
                  <tr key={item.id}>
                    <td>{item.product_name}</td>
                    <td className="text-right">{formatPrice(item.product_price_cents)}</td>
                    <td className="text-right">
                      {item.purchased_at ? new Date(item.purchased_at).toLocaleDateString() : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </Layout>
  );
};
