import * as React from "react";

import { isValidEmail } from "$app/utils/email";

import { Button } from "$app/components/Button";
import { useClientAlert } from "$app/components/ClientAlertProvider";

type EmailSectionProps = {
  label: string;
  email: string;
  onSave: ((email: string) => Promise<void>) | null;
  canContact?: boolean;
  onChangeCanContact?: (canContact: boolean) => Promise<void>;
};

const EmailSection = ({ label, email: currentEmail, onSave, canContact, onChangeCanContact }: EmailSectionProps) => {
  const [email, setEmail] = React.useState(currentEmail);
  const [isEditing, setIsEditing] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(false);

  const { showAlert } = useClientAlert();

  const handleSave = async () => {
    if (!onSave) return;

    const emailError =
      email.length === 0 ? "Email must be provided" : !isValidEmail(email) ? "Please enter a valid email" : null;

    if (emailError) {
      showAlert(emailError, "error");
      return;
    }

    setIsLoading(true);
    await onSave(email);
    setIsLoading(false);
    setIsEditing(false);
  };

  return (
    <section className="stack">
      <header>
        <h3>{label}</h3>
      </header>
      {isEditing ? (
        <fieldset>
          <input
            type="text"
            value={email}
            onChange={(evt) => setEmail(evt.target.value)}
            disabled={isLoading}
            placeholder={label}
          />
          <div
            style={{
              width: "100%",
              display: "grid",
              gap: "var(--spacer-2)",
              gridTemplateColumns: "repeat(auto-fit, minmax(var(--dynamic-grid), 1fr))",
            }}
          >
            <Button onClick={() => setIsEditing(false)} disabled={isLoading}>
              Cancel
            </Button>
            <Button color="primary" onClick={() => void handleSave()} disabled={isLoading}>
              Save
            </Button>
          </div>
        </fieldset>
      ) : (
        <section>
          <h5>{currentEmail}</h5>
          {onSave ? (
            <button className="link" onClick={() => setIsEditing(true)}>
              Edit
            </button>
          ) : (
            <small>
              You cannot change the email of this purchase, because it was made by an existing user. Please ask them to
              go to gumroad.com/settings to update their email.
            </small>
          )}
        </section>
      )}
      {onChangeCanContact ? (
        <section>
          <fieldset role="group">
            <label>
              Receives emails
              <input
                type="checkbox"
                checked={canContact}
                onChange={(evt) => {
                  setIsLoading(true);
                  void onChangeCanContact(evt.target.checked).then(() => setIsLoading(false));
                }}
                disabled={isLoading}
              />
            </label>
          </fieldset>
        </section>
      ) : null}
    </section>
  );
};

export default EmailSection;
