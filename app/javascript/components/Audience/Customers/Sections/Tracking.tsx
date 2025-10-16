import * as React from "react";
import { Tracking } from "$app/data/customers";
import { Button, NavigationButton } from "$app/components/Button";

type TrackingSectionProps = {
  tracking: Tracking;
  onMarkShipped: (url: string) => Promise<void>;
};

const TrackingSection = ({
  tracking,
  onMarkShipped,
}: TrackingSectionProps) => {
  const [url, setUrl] = React.useState((tracking.shipped ? tracking.url : "") ?? "");
  const [isLoading, setIsLoading] = React.useState(false);

  const handleSave = async () => {
    setIsLoading(true);
    await onMarkShipped(url);
    setIsLoading(false);
  };

  return (
    <section className="stack">
      <h3>Tracking information</h3>
      {tracking.shipped ? (
        tracking.url ? (
          <div>
            <NavigationButton color="primary" href={tracking.url} target="_blank">
              Track shipment
            </NavigationButton>
          </div>
        ) : (
          <div>
            <div role="status" className="success">
              Shipped
            </div>
          </div>
        )
      ) : (
        <div>
          <fieldset>
            <input
              type="text"
              placeholder="Tracking URL (optional)"
              value={url}
              onChange={(evt) => setUrl(evt.target.value)}
            />
            <Button color="primary" disabled={isLoading} onClick={() => void handleSave()}>
              Mark as shipped
            </Button>
          </fieldset>
        </div>
      )}
    </section>
  );
};

export default TrackingSection;
