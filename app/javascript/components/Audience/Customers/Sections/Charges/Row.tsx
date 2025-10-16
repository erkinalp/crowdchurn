import * as React from "react";

import { Charge } from "$app/data/customers";

import { Icon } from "$app/components/Icons";

import { useUserAgentInfo } from "$app/components/UserAgent";
import { WithTooltip } from "$app/components/WithTooltip";

import { formatPrice } from "$app/components/Audience/Customers";

import PingButton from "$app/components/Audience/Customers/PingButton";
import RefundForm from "$app/components/Audience/Customers/RefundForm";

type ChargeRowProps = {
  purchase: Charge;
  customerEmail: string;
  onChange: (update: Partial<Charge>) => void;
  showRefundFeeNotice: boolean;
  canPing: boolean;
};

const ChargeRow = ({
  purchase,
  customerEmail,
  onChange,
  showRefundFeeNotice,
  canPing,
}: ChargeRowProps) => {
  const [isRefunding, setIsRefunding] = React.useState(false);
  const userAgentInfo = useUserAgentInfo();

  return (
    <>
      <section key={purchase.id}>
        <section style={{ display: "flex", gap: "var(--spacer-1)", alignItems: "center" }}>
          <h5>
            {formatPrice(purchase.amount_refundable, purchase.currency_type)} on{" "}
            {new Date(purchase.created_at).toLocaleDateString(userAgentInfo.locale, {
              year: "numeric",
              month: "numeric",
              day: "numeric",
            })}
          </h5>

          <a
            href={
              purchase.transaction_url_for_seller ?? Routes.receipt_purchase_path(purchase.id, { email: customerEmail })
            }
            target="_blank"
            rel="noreferrer"
            aria-label="Transaction"
          >
            <Icon name="arrow-up-right-square" />
          </a>
          {purchase.partially_refunded ? (
            <span className="pill small">Partial refund</span>
          ) : purchase.refunded ? (
            <span className="pill small">Refunded</span>
          ) : null}
          {purchase.is_upgrade_purchase ? (
            <WithTooltip tip="This is an upgrade charge, generated when the subscriber upgraded to a more expensive plan.">
              <span className="pill small">Upgrade</span>
            </WithTooltip>
          ) : null}
          {purchase.chargedback ? <span className="pill small">Chargedback</span> : null}
        </section>
        {!purchase.refunded && !purchase.chargedback && purchase.amount_refundable > 0 ? (
          <button className="link" onClick={() => setIsRefunding((prev) => !prev)}>
            Refund Options
          </button>
        ) : null}
        {canPing ? <PingButton purchaseId={purchase.id} /> : null}
      </section>
      {isRefunding ? (
        <RefundForm
          purchaseId={purchase.id}
          currencyType={purchase.currency_type}
          amountRefundable={purchase.amount_refundable}
          showRefundFeeNotice={showRefundFeeNotice}
          paypalRefundExpired={purchase.paypal_refund_expired}
          modalTitle="Charge refund"
          modalText="Would you like to confirm this charge refund?"
          onChange={(amountRefundable) => {
            onChange({
              amount_refundable: amountRefundable,
              refunded: amountRefundable === 0,
              partially_refunded: amountRefundable > 0 && amountRefundable < purchase.amount_refundable,
            });
            setIsRefunding(false);
          }}
          onClose={() => setIsRefunding(false)}
        />
      ) : null}
    </>
  );
};

export default ChargeRow;
