import React from "react";

import { AdminActionButton } from "$app/components/Admin/ActionButton";
import { type Purchase } from "$app/components/Admin/Purchases/PurchaseDetails";

type AdminPurchasesActionsProps = {
  purchase: Purchase;
};

const AdminPurchasesActions = ({ purchase }: AdminPurchasesActionsProps) => (
  <>
    {purchase.can_force_update || purchase.failed ? (
      <AdminActionButton
        url={Routes.sync_status_with_charge_processor_admin_purchase_path(purchase.id)}
        label="Sync with Stripe/PayPal"
        loading="syncing..."
        done="synced!"
        confirm_message="Are you sure you want to sync this purchase's state with Stripe/PayPal?"
        success_message="synced!"
      />
    ) : null}

    {purchase.successful && !purchase.stripe_refunded ? (
      <>
        <AdminActionButton
          url={Routes.refund_admin_purchase_path(purchase.id)}
          label="Refund"
          loading="Refunding..."
          done="Refunded!"
          confirm_message="Are you sure you want to refund this purchase?"
          success_message="Refunded!"
        />
        <AdminActionButton
          url={Routes.refund_for_fraud_admin_purchase_path(purchase.id)}
          label="Refund for Fraud"
          loading="Refunding..."
          done="Refunded!"
          confirm_message="Are you sure you want to refund this purchase for fraud?"
          success_message="Refunded!"
        />
        <AdminActionButton
          url={Routes.refund_taxes_only_admin_purchase_path(purchase.id)}
          label="Refund taxes only"
          loading="Refunding taxes..."
          done="Taxes refunded!"
          confirm_message="Are you sure you want to refund only the taxes for this purchase?"
          success_message="Taxes refunded!"
        />
        <AdminActionButton
          url={Routes.refund_admin_cards_path({ stripe_fingerprint: purchase.stripe_fingerprint })}
          label="Refund Card for Fraud"
          loading="Refunding..."
          done="Refunding purchases!"
          confirm_message="Are you sure you want to Mass-refund for fraud all purchases associated with this purchase's card?"
          success_message="Refunding purchases!"
        />
      </>
    ) : null}

    {purchase.subscription &&
    !purchase.subscription.cancelled_at &&
    !purchase.subscription.failed_at &&
    !purchase.subscription.ended_at ? (
      <>
        <AdminActionButton
          url={Routes.cancel_subscription_admin_purchase_path(purchase.id, { by_seller: false })}
          label="Cancel subscription for buyer"
          loading="Canceling..."
          done="Canceled!"
          confirm_message="Are you sure you want to cancel this subscription on behalf of the buyer?"
          success_message="Canceled!"
        />
        <AdminActionButton
          url={Routes.cancel_subscription_admin_purchase_path(purchase.id, { by_seller: true })}
          label="Cancel subscription for seller"
          loading="Canceling..."
          done="Canceled!"
          confirm_message="Are you sure you want to cancel this subscription on behalf of the seller?"
          success_message="Canceled!"
        />
      </>
    ) : null}

    {purchase.buyer_blocked ? (
      <AdminActionButton
        url={Routes.unblock_buyer_admin_purchase_path(purchase.id)}
        label="Unblock buyer"
        loading="Unblocking buyer..."
        done="Buyer unblocked!"
        success_message="Buyer unblocked!"
      />
    ) : null}

    {!purchase.buyer_blocked && (
      <AdminActionButton
        url={Routes.block_buyer_admin_purchase_path(purchase.id)}
        label="Block buyer"
        loading="Blocking buyer..."
        done="Buyer blocked!"
        confirm_message="This will fully block this buyer's emails, GUID, and IP addresses. Proceed?"
        success_message="Buyer blocked!"
      />
    )}

    {purchase.is_deleted_by_buyer ? (
      <AdminActionButton
        url={Routes.undelete_admin_purchase_path(purchase.id)}
        label="Undelete"
        loading="Undeleting..."
        done="Undeleted!"
        confirm_message="Are you sure you want to undelete this purchase?"
        success_message="Undeleted!"
      />
    ) : null}

    {purchase.successful ? (
      <a
        href={Routes.receipt_purchase_path(purchase.external_id)}
        target="_blank"
        className="button small"
        rel="noreferrer"
      >
        Go to Receipt
      </a>
    ) : null}
  </>
);

export default AdminPurchasesActions;
