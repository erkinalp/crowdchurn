import * as React from "react";
import { Address } from "$app/data/customers";
import { Button } from "$app/components/Button";

const AddressSection = ({
  address: currentAddress,
  price,
  onSave,
  countries,
}: {
  address: Address;
  price: string;
  onSave: (address: Address) => Promise<void>;
  countries: string[];
}) => {
  const uid = React.useId();

  const [address, setAddress] = React.useState(currentAddress);
  const updateShipping = (update: Partial<Address>) => setAddress((prev) => ({ ...prev, ...update }));

  const [isEditing, setIsEditing] = React.useState(false);
  const [isLoading, setIsLoading] = React.useState(false);

  const handleSave = async () => {
    setIsLoading(true);
    await onSave(address);
    setIsLoading(false);
    setIsEditing(false);
  };

  return (
    <section className="stack">
      <header>
        <h3>Shipping address</h3>
      </header>
      {isEditing ? (
        <div>
          <div className="paragraphs">
            <fieldset>
              <legend>
                <label htmlFor={`${uid}-full-name`}>Full name</label>
              </legend>
              <input
                id={`${uid}-full-name`}
                type="text"
                placeholder="Full name"
                value={address.full_name}
                onChange={(evt) => updateShipping({ full_name: evt.target.value })}
              />
            </fieldset>
            <fieldset>
              <legend>
                <label htmlFor={`${uid}-street-address`}>Street address</label>
              </legend>
              <input
                id={`${uid}-street-address`}
                type="text"
                placeholder="Street address"
                value={address.street_address}
                onChange={(evt) => updateShipping({ street_address: evt.target.value })}
              />
            </fieldset>
            <div style={{ display: "grid", gridAutoFlow: "column", gridAutoColumns: "1fr", gap: "var(--spacer-2)" }}>
              <fieldset>
                <legend>
                  <label htmlFor={`${uid}-city`}>City</label>
                </legend>
                <input
                  id={`${uid}-city`}
                  type="text"
                  placeholder="City"
                  value={address.city}
                  onChange={(evt) => updateShipping({ city: evt.target.value })}
                />
              </fieldset>
              <fieldset>
                <legend>
                  <label htmlFor={`${uid}-state`}>State</label>
                </legend>
                <input
                  id={`${uid}-state`}
                  type="text"
                  placeholder="State"
                  value={address.state}
                  onChange={(evt) => updateShipping({ state: evt.target.value })}
                />
              </fieldset>
              <fieldset>
                <legend>
                  <label htmlFor={`${uid}-zip-code`}>ZIP code</label>
                </legend>
                <input
                  id={`${uid}-zip-code`}
                  type="text"
                  placeholder="ZIP code"
                  value={address.zip_code}
                  onChange={(evt) => updateShipping({ zip_code: evt.target.value })}
                />
              </fieldset>
            </div>
            <fieldset>
              <label htmlFor={`${uid}-country`}>Country</label>
              <select
                id={`${uid}-country`}
                value={address.country}
                onChange={(evt) => updateShipping({ country: evt.target.value })}
              >
                {countries.map((country) => (
                  <option value={country} key={country}>
                    {country}
                  </option>
                ))}
              </select>
            </fieldset>
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
          </div>
        </div>
      ) : (
        <div>
          <p>
            {currentAddress.full_name}
            <br />
            {currentAddress.street_address}
            <br />
            {`${currentAddress.city}, ${currentAddress.state} ${currentAddress.zip_code}`}
            <br />
            {currentAddress.country}
          </p>
          <button className="link" onClick={() => setIsEditing(true)}>
            Edit
          </button>
        </div>
      )}
      <div>
        <h5>Shipping charged</h5>
        {price}
      </div>
    </section>
  );
};

export default AddressSection;
