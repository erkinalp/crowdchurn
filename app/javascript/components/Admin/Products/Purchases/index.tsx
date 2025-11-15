import * as React from "react";
import { cast } from "ts-safe-cast";

import { useLazyPaginatedFetch } from "$app/hooks/useLazyFetch";
import { assertResponseError, request, ResponseError } from "$app/utils/request";

import { showAlert } from "$app/components/server-components/Alert";

import AdminProductPurchasesContent from "./Content";
import { type ProductPurchase } from "./Purchase";

type MassRefundResponse = {
  success: boolean;
  message?: string | null;
  batch_id: number;
};

type BatchStatusResponse = {
  id: number;
  status: "pending" | "processing" | "completed" | "failed";
  total_count: number;
  processed_count: number;
  refunded_count: number;
  blocked_count: number;
  failed_count: number;
  errors_by_purchase_id: Record<string, string>;
  error_message?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  created_at: string;
};

type AdminProductPurchasesProps = {
  productId: number;
  isAffiliateUser?: boolean;
  userId: number | null;
};

const AdminProductPurchases = ({ productId, isAffiliateUser = false, userId }: AdminProductPurchasesProps) => {
  const [open, setOpen] = React.useState(false);
  const [selectedPurchaseIds, setSelectedPurchaseIds] = React.useState<Set<number>>(() => new Set());
  const [isMassRefunding, setIsMassRefunding] = React.useState(false);
  const [currentBatchId, setCurrentBatchId] = React.useState<number | null>(null);
  const [batchStatus, setBatchStatus] = React.useState<BatchStatusResponse | null>(null);

  const url =
    userId && isAffiliateUser
      ? Routes.admin_affiliate_product_purchases_path(userId, productId, { format: "json" })
      : Routes.admin_product_purchases_path(productId, { format: "json" });

  const {
    data: purchases,
    setData,
    isLoading,
    fetchNextPage,
    hasMore,
  } = useLazyPaginatedFetch<ProductPurchase[]>([], {
    fetchUnlessLoaded: open,
    url,
    responseParser: (data) => {
      const parsed = cast<{ purchases: ProductPurchase[] }>(data);
      return parsed.purchases;
    },
    mode: "append",
  });

  React.useEffect(() => {
    if (!open) {
      setSelectedPurchaseIds(new Set());
      setCurrentBatchId(null);
      setBatchStatus(null);
    }
  }, [open]);

  React.useEffect(() => {
    setSelectedPurchaseIds((prev) => {
      const allowedIds = new Set(purchases.map((purchase) => purchase.id));
      const next = new Set<number>();
      prev.forEach((id) => {
        if (allowedIds.has(id)) next.add(id);
      });
      return next.size === prev.size ? prev : next;
    });
  }, [purchases]);

  React.useEffect(() => {
    if (!currentBatchId) return;

    const pollBatchStatus = async () => {
      try {
        const response = await request({
          method: "GET",
          accept: "json",
          url: Routes.mass_refund_batch_admin_product_purchases_path(productId, currentBatchId, { format: "json" }),
        });

        const status = cast<BatchStatusResponse>(await response.json());
        setBatchStatus(status);

        if (status.status === "completed" || status.status === "failed") {
          // Final status reached, stop polling
          if (status.status === "completed") {
            showAlert(
              `Mass refund completed. Refunded & blocked: ${status.refunded_count}. Blocked only: ${status.blocked_count}. Failed: ${status.failed_count}.`,
              "success",
            );
          } else {
            showAlert(`Mass refund failed: ${status.error_message}`, "error");
          }

          // Refresh purchases to reflect changes
          setCurrentBatchId(null);
          setBatchStatus(null);
        }
      } catch (error) {
        assertResponseError(error);
        showAlert("Failed to check batch status", "error");
      }
    };

    // Poll immediately and then every 2 seconds
    void pollBatchStatus();
    const interval = setInterval(() => void pollBatchStatus(), 2000);

    return () => clearInterval(interval);
  }, [currentBatchId, productId, setData]);

  const togglePurchaseSelection = React.useCallback((purchaseId: number, selected: boolean) => {
    setSelectedPurchaseIds((prev) => {
      const next = new Set(prev);
      if (selected) {
        next.add(purchaseId);
      } else {
        next.delete(purchaseId);
      }
      return next;
    });
  }, []);

  const clearSelection = React.useCallback(() => setSelectedPurchaseIds(new Set()), []);

  const handleMassRefund = React.useCallback(async () => {
    const selectionCount = selectedPurchaseIds.size;
    if (selectionCount === 0 || isMassRefunding) return;
    const confirmMessage = `Are you sure you want to refund ${selectionCount} ${
      selectionCount === 1 ? "purchase" : "purchases"
    } and block the buyers?`;
    // eslint-disable-next-line no-alert
    if (!confirm(confirmMessage)) {
      return;
    }

    const csrfToken = cast<string>($("meta[name=csrf-token]").attr("content"));
    const purchaseIds = Array.from(selectedPurchaseIds);

    setIsMassRefunding(true);

    try {
      const response = await request({
        url: Routes.mass_refund_admin_product_purchases_path(productId, { format: "json" }),
        method: "POST",
        accept: "json",
        data: {
          authenticity_token: csrfToken,
          purchase_ids: purchaseIds,
        },
      });

      const body = cast<MassRefundResponse>(await response.json());
      if (!response.ok || !body.success) {
        throw new ResponseError(body.message ?? "Something went wrong.");
      }

      showAlert(body.message ?? "Mass refund started.", "success");

      setCurrentBatchId(body.batch_id);
      setSelectedPurchaseIds(new Set());
    } catch (error) {
      assertResponseError(error);
      showAlert(error.message, "error");
    } finally {
      setIsMassRefunding(false);
    }
  }, [isMassRefunding, productId, selectedPurchaseIds]);

  return (
    <>
      <hr />
      <details open={open} onToggle={(e) => setOpen(e.currentTarget.open)}>
        <summary>
          <h3>{isAffiliateUser ? "Affiliate purchases" : "Purchases"}</h3>
        </summary>
        <AdminProductPurchasesContent
          purchases={purchases}
          isLoading={isLoading}
          hasMore={hasMore}
          onLoadMore={() => void fetchNextPage()}
          selectedPurchaseIds={selectedPurchaseIds}
          onToggleSelection={togglePurchaseSelection}
          onMassRefund={() => {
            void handleMassRefund();
          }}
          onClearSelection={clearSelection}
          isMassRefunding={isMassRefunding}
          batchStatus={batchStatus}
        />
      </details>
    </>
  );
};

export default AdminProductPurchases;
