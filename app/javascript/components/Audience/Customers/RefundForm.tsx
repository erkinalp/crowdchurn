import cx from "classnames";
import * as React from "react";

import { refund } from "$app/data/customers";
import {
  CurrencyCode,
  formatPriceCentsWithoutCurrencySymbol,
} from "$app/utils/currency";
import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Modal } from "$app/components/Modal";
import { PriceInput } from "$app/components/PriceInput";
import { WithTooltip } from "$app/components/WithTooltip";
import { useClientAlert } from "$app/components/ClientAlertProvider";

const RefundForm = ({
  purchaseId,
  currencyType,
  amountRefundable,
  showRefundFeeNotice,
  paypalRefundExpired,
  modalTitle,
  modalText,
  onChange,
  onClose,
}: {
  purchaseId: string;
  currencyType: CurrencyCode;
  amountRefundable: number;
  showRefundFeeNotice: boolean;
  paypalRefundExpired: boolean;
  modalTitle: string;
  modalText: string;
  onChange: (amountRefundable: number) => void;
  onClose?: () => void;
}) => {
  const [isLoading, setIsLoading] = React.useState(false);
  const [isModalShowing, setIsModalShowing] = React.useState(false);
  const [refundAmountCents, setRefundAmountCents] = React.useState<{ value: number | null; error?: boolean }>({
    value: amountRefundable,
  });

  const refundAmountRemaining = amountRefundable - (refundAmountCents.value ?? 0);
  const isPartialRefund = refundAmountRemaining > 0;
  const { showAlert } = useClientAlert();

  const handleRefund = async () => {
    if (!refundAmountCents.value) {
      setIsModalShowing(false);
      return setRefundAmountCents((prev) => ({ ...prev, error: true }));
    }
    try {
      setIsLoading(true);
      await refund(purchaseId, refundAmountCents.value / 100.0);
      const refundAmountRemaining = amountRefundable - refundAmountCents.value;
      onChange(refundAmountRemaining);
      setRefundAmountCents({ value: refundAmountRemaining });
      showAlert("Purchase successfully refunded.", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    }
    setIsLoading(false);
    setIsModalShowing(false);
  };

  const refundButton = (
    <Button color="primary" onClick={() => setIsModalShowing(true)} disabled={isLoading || paypalRefundExpired}>
      {isLoading ? "Refunding..." : isPartialRefund ? "Issue partial refund" : "Refund fully"}
    </Button>
  );

  return (
    <>
      <fieldset className={cx({ danger: refundAmountCents.error })}>
        <PriceInput
          cents={refundAmountCents.value}
          onChange={(value) => setRefundAmountCents({ value })}
          currencyCode={currencyType}
          placeholder={formatPriceCentsWithoutCurrencySymbol(currencyType, amountRefundable)}
          hasError={refundAmountCents.error ?? false}
        />
        <div
          style={{
            width: "100%",
            display: "grid",
            gap: "var(--spacer-2)",
            gridTemplateColumns: "repeat(auto-fit, minmax(var(--dynamic-grid), 1fr))",
          }}
        >
          {onClose ? (
            <Button onClick={onClose} disabled={isLoading}>
              Cancel
            </Button>
          ) : null}
          {paypalRefundExpired ? (
            <WithTooltip tip="PayPal refunds aren't available after 6 months." position="top">
              {refundButton}
            </WithTooltip>
          ) : (
            refundButton
          )}
        </div>
        {showRefundFeeNotice ? (
          <div role="status" className="info">
            <p>
              Going forward, Gumroad does not return any fees when a payment is refunded.{" "}
              <a href="/help/article/47-how-to-refund-a-customer" target="_blank" rel="noreferrer">
                Learn more
              </a>
            </p>
          </div>
        ) : null}
      </fieldset>
      <div style={{ display: "contents" }}>
        <Modal
          open={isModalShowing}
          onClose={() => setIsModalShowing(false)}
          title={modalTitle}
          footer={
            <>
              <Button onClick={() => setIsModalShowing(false)} disabled={isLoading}>
                Cancel
              </Button>
              <Button color="accent" onClick={() => void handleRefund()} disabled={isLoading}>
                {isLoading ? "Refunding..." : "Confirm refund"}
              </Button>
            </>
          }
        >
          {modalText}
        </Modal>
      </div>
    </>
  );
};

export default RefundForm;
