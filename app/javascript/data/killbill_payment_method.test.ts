import typia from "typia";
import { describe, expect, it, vi } from "vitest";

import { prepareFutureCharges } from "$app/data/card_payment_method_data";
import { AnyPaymentMethodParams, serializeCardParamsIntoQueryParamsObject } from "$app/data/payment_method_params";
import {
  AnyPaymentMethodResult,
  getPaymentMethodResult,
  getReusablePaymentMethodResult,
  NewKillBillSelectedPaymentMethod,
} from "$app/data/payment_method_result";
import { getPaymentDetailsSource } from "$app/data/purchase";

vi.mock("$app/data/card_payment_method_data", () => ({
  confirmCardIfNeeded: vi.fn(),
  prepareCardPaymentMethodData: vi.fn(),
  prepareFutureCharges: vi.fn(),
  preparePaymentElementPaymentMethodData: vi.fn(),
}));

const selected: NewKillBillSelectedPaymentMethod = {
  type: "killbill",
  paymentMethodId: "kb-payment-method",
  accountId: "kb-account",
  walletAddress: "refund-wallet",
  isCryptocurrency: true,
};

const params = {
  status: "success",
  type: "killbill",
  killbill_payment_method_id: "kb-payment-method",
  killbill_account_id: "kb-account",
  wallet_address: "refund-wallet",
  is_cryptocurrency: true,
};

describe("Kill Bill payment compatibility", () => {
  it("retains the Kill Bill discriminant and crypto refund details in one-off and reusable results", async () => {
    const expected = { type: "new", cardParamsResult: { type: "killbill", cardParams: params } };
    expect(await getPaymentMethodResult(selected)).toEqual(expected);
    expect(await getReusablePaymentMethodResult(selected, { products: [] })).toEqual(expected);
    expect(prepareFutureCharges).not.toHaveBeenCalled();
    expect(typia.assert<AnyPaymentMethodResult>(expected)).toEqual(expected);
  });

  it("validates and serializes Kill Bill params for account and subscription endpoints", () => {
    const validated = typia.assert<AnyPaymentMethodParams>(params);
    expect(serializeCardParamsIntoQueryParamsObject(validated)).toEqual({
      killbill_payment_method_id: "kb-payment-method",
      killbill_account_id: "kb-account",
      wallet_address: "refund-wallet",
      is_cryptocurrency: true,
    });
    expect(() => typia.assert<AnyPaymentMethodParams>({ ...params, killbill_account_id: null })).toThrow();
  });

  it("does not classify Kill Bill as a Stripe collection source", async () => {
    const result = await getPaymentMethodResult(selected);
    expect(getPaymentDetailsSource(result, false)).toBeNull();
    expect(getPaymentDetailsSource(result, true)).toBeNull();
  });
});
