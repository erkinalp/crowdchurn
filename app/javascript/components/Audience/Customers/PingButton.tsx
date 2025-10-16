import React from 'react';
import { useClientAlert } from '$app/components/ClientAlertProvider';
import { assertResponseError } from '$app/utils/request';
import { Button } from '$app/components/Button';
import { resendPing } from "$app/data/customers";

type PingButtonProps = {
  purchaseId: string;
};

const PingButton = ({ purchaseId }: PingButtonProps) => {
  const [isLoading, setIsLoading] = React.useState(false);
  const { showAlert } = useClientAlert();

  const handleClick = async () => {
    setIsLoading(true);
    try {
      await resendPing(purchaseId);
      showAlert("Ping resent.", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <Button color="primary" disabled={isLoading} onClick={() => void handleClick()}>
      {isLoading ? "Resending ping..." : "Resend ping"}
    </Button>
  );
};

export default PingButton;
