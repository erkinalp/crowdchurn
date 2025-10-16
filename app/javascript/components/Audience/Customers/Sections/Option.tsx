import cx from "classnames";
import * as React from "react";

import {
  Option,
  getOptions,
  updateOption,
} from "$app/data/customers";

import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Progress } from "$app/components/Progress";
import { useRunOnce } from "$app/components/useRunOnce";
import { useClientAlert } from "$app/components/ClientAlertProvider";

type OptionSectionProps = {
  option: Option | null;
  onChange: (option: Option) => void;
  purchaseId: string;
  productPermalink: string;
  isSubscription: boolean;
  quantity: number;
};

const OptionSection = ({
  option,
  onChange,
  purchaseId,
  productPermalink,
  isSubscription,
  quantity,
}: OptionSectionProps) => {
  const [options, setOptions] = React.useState<Option[]>([]);
  const [selectedOptionId, setSelectedOptionId] = React.useState<{ value: string | null; error?: boolean }>({
    value: option?.id ?? null,
  });
  const [isEditing, setIsEditing] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(false);

  const { showAlert } = useClientAlert();

  useRunOnce(
    () =>
      void getOptions(productPermalink).then(
        (options) => setOptions(option && !options.some(({ id }) => id === option.id) ? [option, ...options] : options),
        (e: unknown) => {
          assertResponseError(e);
          showAlert(e.message, "error");
        },
      ),
  );

  const handleSave = async () => {
    const option = options.find(({ id }) => id === selectedOptionId.value);
    if (!option) return setSelectedOptionId((prev) => ({ ...prev, error: true }));
    try {
      setIsLoading(true);
      await updateOption(purchaseId, option.id, quantity);
      showAlert("Saved variant", "success");
      onChange(option);
      setIsEditing(false);
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    }
    setIsLoading(false);
  };

  const title = isSubscription ? "Tier" : "Version";

  return (
    <section className="stack">
      <header>
        <h3>{title}</h3>
      </header>
      <section>
        {options.length > 0 ? (
          isEditing ? (
            <fieldset className={cx({ danger: selectedOptionId.error })}>
              <select
                value={selectedOptionId.value ?? "None selected"}
                name={title}
                onChange={(evt) => setSelectedOptionId({ value: evt.target.value })}
                aria-invalid={selectedOptionId.error}
              >
                {!selectedOptionId.value ? <option>None selected</option> : null}
                {options.map((option) => (
                  <option value={option.id} key={option.id}>
                    {option.name}
                  </option>
                ))}
              </select>
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
            <>
              <h5>{option?.name ?? "None selected"}</h5>
              <button className="link" onClick={() => setIsEditing(true)}>
                Edit
              </button>
            </>
          )
        ) : (
          <div className="text-center">
            <Progress width="2em" />
          </div>
        )}
      </section>
    </section>
  );
};

export default OptionSection;
