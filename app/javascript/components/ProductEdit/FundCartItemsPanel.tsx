import { Trash } from "@boxicons/react";
import * as React from "react";
import { assert } from "typia";

import { request, ResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Layout } from "$app/components/ProductEdit/Layout";
import { showAlert } from "$app/components/server-components/Alert";
import { DefinitionList } from "$app/components/ui/DefinitionList";
import { Input } from "$app/components/ui/Input";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "$app/components/ui/Table";

type Amount = { subunits: string; currency: string; currency_exponent: number; formatted: string };
type Reason = { code: string; message: string };
export type FundCartItem = {
  id: string;
  product_id: string;
  product_name: string;
  product_price_cents: number;
  product_native_type: string;
  product_currency: string;
  product_price: Amount;
  state: string;
  purchased_at: string | null;
  created_at: string;
  pending_reason: Reason | null;
  route_status: { state: "supported" | "unsupported" | "reconciling"; route: string | null; reason: Reason | null };
  can_remove: boolean;
  can_request_cancellation: boolean;
  removal_requires_cancellation: boolean;
  settlement: { id: string; state: string; cancel_requested: boolean; amount: Amount } | null;
};

export type FundCartData = {
  items: FundCartItem[];
  balance_subunits: number;
  available_subunits: number;
  pending_subunits: number;
  reserved_subunits: number;
  debt_subunits: number;
  currency: string;
  currency_exponent: number;
  ledger_state: "legacy" | "active" | "reconciling" | "paused";
  amounts: { available: Amount; pending: Amount; reserved: Amount; debt: Amount };
};

export const FundCartItemsPanel = ({ fundCartId }: { fundCartId: string }) => {
  const [data, setData] = React.useState<FundCartData | null>(null);
  const [loading, setLoading] = React.useState(true);
  const [productInput, setProductInput] = React.useState("");
  const [addError, setAddError] = React.useState<string | null>(null);
  const [adding, setAdding] = React.useState(false);
  const [removingIds, setRemovingIds] = React.useState<Set<string>>(new Set());

  const fetchItems = React.useCallback(async () => {
    setLoading(true);
    try {
      const resp = await request({
        method: "GET",
        accept: "json",
        url: `/api/internal/fund_carts/${fundCartId}/items`,
      });
      if (!resp.ok) throw new ResponseError("Failed to load fund cart items.");
      setData(assert<FundCartData>(await resp.json()));
    } catch {
      setData(null);
      showAlert("Failed to load fund cart items. Refresh to check the current funding status.", "error");
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
      if (!resp.ok) {
        const json = assert<{ error?: string }>(await resp.json());
        setAddError(json.error || "Failed to add item.");
      } else {
        setProductInput("");
        await fetchItems();
      }
    } catch (e) {
      setAddError(e instanceof ResponseError ? e.message : "Failed to add item.");
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
      if (!resp.ok) {
        const json = assert<{ error?: string }>(await resp.json());
        showAlert(json.error || "Failed to remove item.", "error");
      }
    } catch (e) {
      showAlert(e instanceof ResponseError ? e.message : "Failed to remove item.", "error");
    } finally {
      // An unsuccessful cancellation can still change the reconciliation state.
      await fetchItems();
      setRemovingIds((prev) => {
        const next = new Set(prev);
        next.delete(itemId);
        return next;
      });
    }
  };

  const pendingItems = data?.items.filter((i) => i.state === "pending") ?? [];
  const purchasedItems = data?.items.filter((i) => i.state === "purchased") ?? [];

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
        <section className="p-4! md:p-8!" aria-label="Fund balances">
          <h2>Fund balance</h2>
          <Button onClick={() => void fetchItems()}>Refresh status</Button>
          {data ? (
            <>
              <DefinitionList>
                <dt>Available to spend</dt>
                <dd>{data.amounts.available.formatted}</dd>
                <dt>Pending confirmation</dt>
                <dd>{data.amounts.pending.formatted}</dd>
                <dt>Reserved for items</dt>
                <dd>{data.amounts.reserved.formatted}</dd>
                <dt>Amount owed by cart owner</dt>
                <dd>{data.amounts.debt.formatted}</dd>
              </DefinitionList>
              <p>Only available funds can be spent. Pending and reserved amounts are not spendable.</p>
              <p>
                Contributions fund eligible items after the contribution's taxes and fees, not at their gross price.
              </p>
              {data.ledger_state !== "active" ? (
                <p role="status">
                  This cart is {data.ledger_state === "paused" ? "paused" : "awaiting reconciliation"}. Contact support
                  before accepting contributions. Historical balances are not spendable.
                </p>
              ) : null}
              {data.amounts.debt.subunits !== "0" ? (
                <p role="status">
                  Spending is blocked until the cart owner's contribution reversal debt is resolved. Contact support;
                  the original contribution merchant retains payment-provider liability.
                </p>
              ) : null}
            </>
          ) : (
            <p role="status">Funding status is unavailable. Refresh before making changes.</p>
          )}
        </section>

        <section className="p-4! md:p-8!">
          <h2>Add item</h2>
          <div className="flex gap-2">
            <Input
              type="text"
              className="flex-1"
              aria-label="Product ID"
              placeholder="Product ID"
              value={productInput}
              onChange={(e) => {
                setProductInput(e.target.value);
                setAddError(null);
              }}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  if (data && !adding) void handleAdd();
                }
              }}
            />
            <Button color="primary" disabled={!data || adding || !productInput.trim()} onClick={() => void handleAdd()}>
              {adding ? "Adding..." : "Add"}
            </Button>
          </div>
          {addError ? (
            <p role="alert" className="mt-2 text-sm text-red-500">
              {addError}
            </p>
          ) : null}
        </section>

        <section className="p-4! md:p-8!">
          <h2>Pending items ({pendingItems.length})</h2>
          <p>Unsupported items can stay on your wishlist. Ordinary checkout remains available through their sellers.</p>
          {pendingItems.length === 0 ? (
            <p className="text-muted">No pending items.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="text-left">Product</TableHead>
                  <TableHead className="text-right">Price / quoted total</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>
                    <span className="sr-only">Actions</span>
                  </TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {pendingItems.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell>{item.product_name}</TableCell>
                    <TableCell className="text-right">
                      {item.settlement && item.settlement.state !== "cancelled"
                        ? item.settlement.amount.formatted
                        : item.product_price.formatted}
                      {!item.settlement || item.settlement.state === "cancelled" ? (
                        <small className="block">Before tax and shipping</small>
                      ) : (
                        <small className="block">Quoted total</small>
                      )}
                    </TableCell>
                    <TableCell>
                      {item.route_status.state !== "supported" ? (
                        <strong>
                          {item.route_status.state === "reconciling" ? "Reconciling" : "Unsupported route"}
                        </strong>
                      ) : null}
                      <p>{item.pending_reason?.message}</p>
                      {item.route_status.reason && item.route_status.reason.code !== item.pending_reason?.code ? (
                        <p>{item.route_status.reason.message}</p>
                      ) : null}
                    </TableCell>
                    <TableCell className="text-right">
                      <Button
                        color="danger"
                        aria-label={
                          item.can_request_cancellation
                            ? `Request cancellation for ${item.product_name}`
                            : item.removal_requires_cancellation
                              ? `Cancel reservation and remove ${item.product_name}`
                              : `Remove ${item.product_name}`
                        }
                        disabled={removingIds.has(item.id) || (!item.can_remove && !item.can_request_cancellation)}
                        onClick={() => void handleRemove(item.id)}
                      >
                        <Trash className="size-5" />
                        {item.can_request_cancellation
                          ? "Request cancellation"
                          : item.removal_requires_cancellation
                            ? "Cancel and remove"
                            : "Remove"}
                      </Button>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </section>

        <section className="p-4! md:p-8!">
          <h2>Purchased items ({purchasedItems.length})</h2>
          {purchasedItems.length === 0 ? (
            <p className="text-muted">No purchased items yet.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="text-left">Product</TableHead>
                  <TableHead className="text-right">Paid total</TableHead>
                  <TableHead className="text-right">Purchased</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {purchasedItems.map((item) => (
                  <TableRow key={item.id}>
                    <TableCell>{item.product_name}</TableCell>
                    <TableCell className="text-right">
                      {item.settlement?.amount.formatted ?? "Historical purchase — see receipt"}
                    </TableCell>
                    <TableCell className="text-right">
                      {item.purchased_at ? new Date(item.purchased_at).toLocaleDateString() : "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </section>
      </div>
    </Layout>
  );
};
