import React from "react";

import { Button } from "$app/components/Button";
import { LoadingSpinner } from "$app/components/LoadingSpinner";

import AdminProductPurchase, { ProductPurchase } from "./Purchase";

type AdminProductPurchasesContentProps = {
  purchases: ProductPurchase[];
  isLoading: boolean;
  hasMore: boolean;
  onLoadMore: () => void;
  selectedPurchaseExternalIds: string[];
  onToggleSelection: (purchaseId: string, selected: boolean) => void;
  onMassRefund: () => void;
  onClearSelection: () => void;
  onSelectAll: () => void;
  isMassRefunding: boolean;
};

const AdminProductPurchasesContent = ({
  purchases,
  isLoading,
  hasMore,
  onLoadMore,
  selectedPurchaseExternalIds,
  onToggleSelection,
  onMassRefund,
  onClearSelection,
  onSelectAll,
  isMassRefunding,
}: AdminProductPurchasesContentProps) => {
  if (purchases.length === 0 && !isLoading)
    return (
      <div className="info" role="status">
        No purchases have been made.
      </div>
    );

  const selectedCount = selectedPurchaseExternalIds.length;
  const selectablePurchases = purchases.filter((p) => p.stripe_refunded !== true);
  const allSelectableSelected = selectablePurchases.every((p) => selectedPurchaseExternalIds.includes(p.external_id));

  return (
    <div className="flex flex-col gap-4">
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
          {selectedCount > 0
            ? `${selectedCount} ${selectedCount === 1 ? "purchase selected" : "purchases selected"}`
            : "Select purchases to refund for fraud"}
        </div>
        <div className="button-group">
          {!allSelectableSelected && selectablePurchases.length > 0 ? (
            <Button small outline onClick={onSelectAll} disabled={isMassRefunding}>
              Select all
            </Button>
          ) : null}
          {selectedCount > 0 ? (
            <Button small outline onClick={onClearSelection} disabled={isMassRefunding}>
              Clear selection
            </Button>
          ) : null}
          <Button small onClick={onMassRefund} disabled={selectedCount === 0 || isMassRefunding}>
            {isMassRefunding ? "Starting..." : "Refund for Fraud"}
          </Button>
        </div>
      </div>

      <div className="stack">
        {purchases.map((purchase) => (
          <AdminProductPurchase
            key={purchase.external_id}
            purchase={purchase}
            isSelected={selectedPurchaseExternalIds.includes(purchase.external_id)}
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
