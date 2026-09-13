// @vitest-environment happy-dom

import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import * as React from "react";
import { afterEach, beforeEach, expect, it, vi } from "vitest";

import { request } from "$app/utils/request";

import {
  FundCartItemsPanel,
  type FundCartData,
  type FundCartItem,
} from "$app/components/ProductEdit/FundCartItemsPanel";
import { showAlert } from "$app/components/server-components/Alert";

vi.mock("$app/components/ProductEdit/Layout", () => ({
  Layout: ({ children }: { children: React.ReactNode }) => <div>{children}</div>,
}));
vi.mock("$app/components/server-components/Alert", () => ({ showAlert: vi.fn() }));
vi.mock("$app/utils/request", async (importOriginal) => ({
  ...(await importOriginal<typeof import("$app/utils/request")>()),
  request: vi.fn(),
}));

const amount = (subunits: string, formatted: string): FundCartData["amounts"]["available"] => ({
  subunits,
  formatted,
  currency: "usd",
  currency_exponent: 2,
});
const pendingItem = (): FundCartItem => ({
  id: "item-one",
  product_id: "product-one",
  product_name: "A book",
  product_price_cents: 1000,
  product_native_type: "digital",
  product_currency: "usd",
  product_price: amount("1000", "10.00 USD"),
  state: "pending",
  purchased_at: null,
  created_at: "2026-01-01T00:00:00Z",
  pending_reason: {
    code: "variant_selection_required",
    message: "This item needs a version selection. Use ordinary checkout or contact support.",
  },
  route_status: { state: "supported", route: "operator_stripe_internal_v1", reason: null },
  can_remove: true,
  can_request_cancellation: false,
  removal_requires_cancellation: false,
  settlement: null,
});
const cartData = (): FundCartData => ({
  items: [pendingItem()],
  balance_subunits: 999999,
  available_subunits: 0,
  pending_subunits: 700,
  reserved_subunits: 1000,
  debt_subunits: 500,
  currency: "usd",
  currency_exponent: 2,
  ledger_state: "active",
  amounts: {
    available: amount("0", "0.00 USD"),
    pending: amount("700", "7.00 USD"),
    reserved: amount("1000", "10.00 USD"),
    debt: amount("500", "5.00 USD"),
  },
});
const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

beforeEach(() => vi.resetAllMocks());
afterEach(cleanup);

it("displays exact categorized amounts, not a stale legacy balance or pending funds as spendable", async () => {
  vi.mocked(request).mockResolvedValue(respond(cartData()));
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  const balances = await screen.findByRole("region", { name: "Fund balances" });
  expect(within(balances).getByText("Available to spend").nextElementSibling?.textContent).toBe("0.00 USD");
  expect(within(balances).getByText("Pending confirmation").nextElementSibling?.textContent).toBe("7.00 USD");
  expect(within(balances).getByText("Reserved for items").nextElementSibling?.textContent).toBe("10.00 USD");
  expect(within(balances).getByText("Amount owed by cart owner").nextElementSibling?.textContent).toBe("5.00 USD");
  expect(balances.textContent).not.toContain("999999");
  expect(screen.getByText(/Spending is blocked/u).textContent).toContain("original contribution merchant");
  expect(screen.getByText(/needs a version selection/u)).toBeTruthy();
});

it("keeps the currency and precision supplied by the API rather than using the editor's listed currency", async () => {
  const data = cartData();
  data.currency = "eth";
  data.currency_exponent = 18;
  data.ledger_state = "reconciling";
  data.amounts.pending = {
    subunits: "1234567890123456789",
    currency: "eth",
    currency_exponent: 18,
    formatted: "1.234567890123456789 ETH",
  };
  vi.mocked(request).mockResolvedValue(respond(data));
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  expect(await screen.findByText("1.234567890123456789 ETH")).toBeTruthy();
  expect(screen.getByText(/Historical balances are not spendable/u)).toBeTruthy();
});

it("surfaces unsupported merchant routes while keeping the wishlist item removable", async () => {
  const data = cartData();
  const reason = {
    code: "external_merchant_reservation_unverified",
    message: "This merchant's payment route cannot settle fund-cart proceeds. Use ordinary checkout instead.",
  };
  data.items = [
    { ...pendingItem(), route_status: { state: "unsupported", route: null, reason }, pending_reason: reason },
  ];
  vi.mocked(request).mockResolvedValue(respond(data));
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  expect(await screen.findByText("Unsupported route")).toBeTruthy();
  expect(screen.getByText(reason.message)).toBeTruthy();
  expect(screen.getByRole("button", { name: "Remove A book" })).toHaveProperty("disabled", false);
});

it("requests cancellation, shows the conflict, and reloads without pretending the item was removed", async () => {
  const data = cartData();
  const item: FundCartItem = {
    ...pendingItem(),
    can_remove: false,
    can_request_cancellation: true,
    removal_requires_cancellation: true,
    settlement: {
      id: "settlement-one",
      state: "reconciling",
      cancel_requested: false,
      amount: amount("1200", "12.00 USD"),
    },
    pending_reason: {
      code: "settlement_requires_reconciliation",
      message: "The payment outcome needs reconciliation. Funds remain reserved.",
    },
    route_status: { state: "reconciling", route: "operator_stripe_internal_v1", reason: null },
  };
  data.items = [item];
  const refreshed = {
    ...data,
    items: [
      {
        ...item,
        can_request_cancellation: false,
        settlement: {
          ...item.settlement,
          id: "settlement-one",
          state: "reconciling",
          cancel_requested: true,
          amount: amount("1200", "12.00 USD"),
        },
      },
    ],
  };
  vi.mocked(request)
    .mockResolvedValueOnce(respond(data))
    .mockResolvedValueOnce(respond({ error: "Funds remain reserved. Contact support." }, 409))
    .mockResolvedValueOnce(respond(refreshed));
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  fireEvent.click(await screen.findByRole("button", { name: "Request cancellation for A book" }));

  await waitFor(() => expect(request).toHaveBeenCalledTimes(3));
  expect(request).toHaveBeenNthCalledWith(2, {
    method: "DELETE",
    accept: "json",
    url: "/api/internal/fund_carts/cart-one/items/item-one",
  });
  expect(showAlert).toHaveBeenCalledWith("Funds remain reserved. Contact support.", "error");
  expect(await screen.findByRole("button", { name: "Cancel reservation and remove A book" })).toHaveProperty(
    "disabled",
    true,
  );
  expect(screen.getByText("Pending items (1)")).toBeTruthy();
  expect(screen.getByText("12.00 USD")).toBeTruthy();
});

it("uses the existing DELETE route to cancel a reservation and refresh the released balance", async () => {
  const data = cartData();
  data.items = [
    {
      ...pendingItem(),
      removal_requires_cancellation: true,
      settlement: {
        id: "settlement-one",
        state: "reserved",
        cancel_requested: false,
        amount: amount("1200", "12.00 USD"),
      },
    },
  ];
  vi.mocked(request)
    .mockResolvedValueOnce(respond(data))
    .mockResolvedValueOnce(respond({ success: true }))
    .mockResolvedValueOnce(
      respond({
        ...data,
        items: [],
        amounts: { ...data.amounts, available: amount("1200", "12.00 USD"), reserved: amount("0", "0.00 USD") },
      }),
    );
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  fireEvent.click(await screen.findByRole("button", { name: "Cancel reservation and remove A book" }));

  expect(await screen.findByText("Pending items (0)")).toBeTruthy();
  const balances = screen.getByRole("region", { name: "Fund balances" });
  expect(within(balances).getByText("Available to spend").nextElementSibling?.textContent).toBe("12.00 USD");
});

it("uses the recorded paid total instead of a changed product price", async () => {
  const data = cartData();
  data.items = [
    {
      ...pendingItem(),
      state: "purchased",
      pending_reason: null,
      can_remove: false,
      product_price: amount("9900", "99.00 USD"),
      settlement: {
        id: "settlement-one",
        state: "settled",
        cancel_requested: false,
        amount: amount("1200", "12.00 USD"),
      },
    },
  ];
  vi.mocked(request).mockResolvedValue(respond(data));
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  expect(await screen.findByText("12.00 USD")).toBeTruthy();
  expect(screen.queryByText("99.00 USD")).toBeNull();
  expect(screen.queryByRole("button", { name: "Remove A book" })).toBeNull();
});

it("does not render a failed response or an old payload as a spendable balance", async () => {
  vi.mocked(request).mockResolvedValue(respond({ items: [], balance_subunits: 5000, currency: "usd" }));
  render(<FundCartItemsPanel fundCartId="cart-one" />);

  expect(await screen.findByText("Funding status is unavailable. Refresh before making changes.")).toBeTruthy();
  expect(screen.queryByText("Available to spend")).toBeNull();
  expect(screen.getByRole("button", { name: "Add" })).toHaveProperty("disabled", true);
});

it("preserves server validation errors when adding a product", async () => {
  vi.mocked(request)
    .mockResolvedValueOnce(respond(cartData()))
    .mockResolvedValueOnce(respond({ error: "Product must be priced in the same currency as the fund cart" }, 422));
  render(<FundCartItemsPanel fundCartId="cart-one" />);
  await screen.findByRole("region", { name: "Fund balances" });
  fireEvent.change(screen.getByRole("textbox", { name: "Product ID" }), { target: { value: "product-two" } });
  fireEvent.click(screen.getByRole("button", { name: "Add" }));

  expect((await screen.findByRole("alert")).textContent).toBe(
    "Product must be priced in the same currency as the fund cart",
  );
  expect(request).toHaveBeenNthCalledWith(2, {
    method: "POST",
    accept: "json",
    url: "/api/internal/fund_carts/cart-one/items",
    data: { product_id: "product-two" },
  });
});
