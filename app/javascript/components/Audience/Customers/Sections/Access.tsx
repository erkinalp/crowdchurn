import * as React from "react";

import {
  revokeAccess,
  undoRevokeAccess,
} from "$app/data/customers";

import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { useClientAlert } from "$app/components/ClientAlertProvider";

type AccessSectionProps = {
  purchaseId: string;
  isAccessRevoked: boolean;
  onChange: (accessRevoked: boolean) => void;
};

const AccessSection = ({ purchaseId, isAccessRevoked, onChange }: AccessSectionProps) => {
  const [isLoading, setIsLoading] = React.useState(false);
  const { showAlert } = useClientAlert();

  const handleClick = async (revoke: boolean) => {
    setIsLoading(true);
    try {
      if (revoke) {
        await revokeAccess(purchaseId);
        showAlert("Access revoked", "success");
        onChange(true);
      } else {
        await undoRevokeAccess(purchaseId);
        showAlert("Access re-enabled", "success");
        onChange(false);
      }
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    }
    setIsLoading(false);
  };

  return (
    <section className="stack">
      <div>
        {isAccessRevoked ? (
          <Button disabled={isLoading} onClick={() => void handleClick(false)}>
            Re-enable access
          </Button>
        ) : (
          <Button color="primary" disabled={isLoading} onClick={() => void handleClick(true)}>
            Revoke access
          </Button>
        )}
      </div>
    </section>
  );
};

export default AccessSection;
