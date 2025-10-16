import * as React from "react";
import { Button } from "$app/components/Button";
import { NumberInput } from "$app/components/NumberInput";

type SeatSectionProps = {
  seats: number;
  onSave: (seats: number) => Promise<void>;
};

const SeatSection = ({ seats: currentSeats, onSave }: SeatSectionProps) => {
  const [seats, setSeats] = React.useState(currentSeats);
  const [isEditing, setIsEditing] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(false);

  const handleSave = async () => {
    setIsLoading(true);
    await onSave(seats);
    setIsLoading(false);
    setIsEditing(false);
  };

  return (
    <section className="stack">
      <header>
        <h3>Seats</h3>
      </header>
      {isEditing ? (
        <fieldset>
          <NumberInput value={seats} onChange={(seats) => setSeats(seats ?? 0)}>
            {(props) => <input type="number" {...props} min={1} aria-label="Seats" />}
          </NumberInput>
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
          <h5>{seats}</h5>
          <button className="link" onClick={() => setIsEditing(true)}>
            Edit
          </button>
        </section>
      )}
    </section>
  );
};

export default SeatSection;
