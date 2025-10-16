import * as React from "react";
import { Button } from "$app/components/Button";
import { License } from "$app/data/customers";

type LicenseSectionProps = {
  license: License;
  onSave: (enabled: boolean) => Promise<void>;
};

const LicenseSection = ({ license, onSave }: LicenseSectionProps) => {
  const [isLoading, setIsLoading] = React.useState(false);

  const handleSave = async (enabled: boolean) => {
    setIsLoading(true);
    await onSave(enabled);
    setIsLoading(false);
  };

  return (
    <section className="stack">
      <header>
        <h3>License key</h3>
      </header>
      <div>
        <pre>
          <code>{license.key}</code>
        </pre>
      </div>
      <div>
        {license.enabled ? (
          <Button color="danger" disabled={isLoading} onClick={() => void handleSave(false)}>
            Disable
          </Button>
        ) : (
          <Button disabled={isLoading} onClick={() => void handleSave(true)}>
            Enable
          </Button>
        )}
      </div>
    </section>
  );
};

export default LicenseSection;
