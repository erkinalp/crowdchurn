import * as React from "react";

import { Button } from "$app/components/Button";
import { Modal } from "$app/components/Modal";

const SubscriptionCancellationSection = ({
  onCancel,
  isInstallmentPlan,
}: {
  onCancel: () => void;
  isInstallmentPlan: boolean;
}) => {
  const [open, setOpen] = React.useState(false);
  const constructor = isInstallmentPlan ? "installment plan" : "subscription";
  return (
    <section className="stack">
      <div>
        <Button color="danger" onClick={() => setOpen(true)}>
          Cancel {constructor}
        </Button>
        <Modal
          open={open}
          title={`Cancel ${constructor}`}
          onClose={() => setOpen(false)}
          footer={
            <>
              <Button onClick={() => setOpen(false)}>Cancel</Button>
              <Button color="accent" onClick={onCancel}>
                Cancel {constructor}
              </Button>
            </>
          }
        >
          Would you like to cancel this {constructor}?
        </Modal>
      </div>
    </section>
  );
};

export default SubscriptionCancellationSection;
