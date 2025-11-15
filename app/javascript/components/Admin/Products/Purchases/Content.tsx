import React from "react";

import { Button } from "$app/components/Button";
import { LoadingSpinner } from "$app/components/LoadingSpinner";

import AdminProductPurchase, { ProductPurchase } from "./Purchase";

type BatchStatus = {
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

type AdminProductPurchasesContentProps = {
  purchases: ProductPurchase[];
  isLoading: boolean;
  hasMore: boolean;
  onLoadMore: () => void;
  selectedPurchaseIds: Set<number>;
  onToggleSelection: (purchaseId: number, selected: boolean) => void;
  onMassRefund: () => void;
  onClearSelection: () => void;
  isMassRefunding: boolean;
  batchStatus: BatchStatus | null;
};

const AdminProductPurchasesContent = ({
  purchases,
  isLoading,
  hasMore,
  onLoadMore,
  selectedPurchaseIds,
  onToggleSelection,
  onMassRefund,
  onClearSelection,
  isMassRefunding,
  batchStatus,
}: AdminProductPurchasesContentProps) => {
  if (purchases.length === 0 && !isLoading)
    return (
      <div className="info" role="status">
        No purchases have been made.
      </div>
    );

  const selectedCount = selectedPurchaseIds.size;
  const isProcessingBatch = batchStatus && batchStatus.status === "processing";

  return (
    <div className="paragraphs">
      <div
        className="mass-refund-toolbar"
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "center",
          gap: "0.75rem",
          flexWrap: "wrap",
        }}
      >
        <div>
          {batchStatus ? (
            <div>
              <div>Mass Refund - {batchStatus.status}</div>
              <div style={{ fontSize: "0.875rem", color: "#666" }}>
                {batchStatus.processed_count} of {batchStatus.total_count} processed
                {batchStatus.status === "completed" && (
                  <span>
                    {" "}
                    • {batchStatus.refunded_count} refunded (and blocked), {batchStatus.blocked_count} blocked only,{" "}
                    {batchStatus.failed_count} failed
                  </span>
                )}
              </div>
            </div>
          ) : selectedCount > 0 ? (
            `${selectedCount} ${selectedCount === 1 ? "purchase selected" : "purchases selected"}`
          ) : (
            "Select purchases to mass refund"
          )}
        </div>
        <div className="button-group">
          {selectedCount > 0 ? (
            <Button small outline onClick={onClearSelection} disabled={Boolean(isMassRefunding || isProcessingBatch)}>
              Clear selection
            </Button>
          ) : null}
          <Button
            small
            color="danger"
            onClick={onMassRefund}
            disabled={selectedCount === 0 || Boolean(isMassRefunding || isProcessingBatch)}
          >
            {isMassRefunding ? "Starting..." : isProcessingBatch ? "Processing..." : "Refund"}
          </Button>
        </div>
      </div>

      <div className="stack">
        {purchases.map((purchase) => (
          <AdminProductPurchase
            key={purchase.id}
            purchase={purchase}
            isSelected={selectedPurchaseIds.has(purchase.id)}
            onToggleSelection={onToggleSelection}
          />
        ))}
      </div>

      {isLoading ? <LoadingSpinner /> : null}

      {hasMore ? (
        <Button small onClick={onLoadMore} disabled={isLoading}>
          {isLoading ? "Loading..." : "Load more"}
        </Button>
      ) : null}
    </div>
  );
};

export default AdminProductPurchasesContent;
