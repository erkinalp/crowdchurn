import * as React from "react";

import { Call, updateCallUrl } from "$app/data/customers";

import { formatCallDate } from "$app/utils/date";
import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { useCurrentSeller } from "$app/components/CurrentSeller";
import { useClientAlert } from "$app/components/ClientAlertProvider";

type CallSectionProps = {
  call: Call;
  onChange: (call: Call) => void;
};

const CallSection = ({ call, onChange }: CallSectionProps) => {
  const currentSeller = useCurrentSeller();
  const [isLoading, setIsLoading] = React.useState(false);
  const [callUrl, setCallUrl] = React.useState(call.call_url ?? "");
  const handleSave = async () => {
    const { showAlert } = useClientAlert();
    setIsLoading(true);
    try {
      await updateCallUrl(call.id, callUrl);
      onChange({ ...call, call_url: callUrl });
      showAlert("Call URL updated!", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    }
    setIsLoading(false);
  };

  return (
    <section className="stack">
      <header>
        <h3>Call</h3>
      </header>
      <section>
        <h5>Start time</h5>
        {formatCallDate(new Date(call.start_time), { timeZone: { userTimeZone: currentSeller?.timeZone.name } })}
      </section>
      <section>
        <h5>End time</h5>
        {formatCallDate(new Date(call.end_time), { timeZone: { userTimeZone: currentSeller?.timeZone.name } })}
      </section>
      <section>
        <form
          onSubmit={(evt) => {
            evt.preventDefault();
            void handleSave();
          }}
        >
          <fieldset>
            <input
              type="text"
              value={callUrl}
              onChange={(evt) => setCallUrl(evt.target.value)}
              placeholder="Call URL"
            />
            <Button color="primary" type="submit" disabled={isLoading}>
              {isLoading ? "Saving..." : "Save"}
            </Button>
          </fieldset>
        </form>
      </section>
    </section>
  );
};

export default CallSection;
