import * as React from "react";

import { type Charge } from "$app/data/customers";
import { Progress } from "$app/components/Progress";

import ChargeRow from "$app/components/Audience/Customers/Sections/Charges/Row";

type ChargesSectionProps = {
  charges: Charge[];
  remainingCharges: number | null;
  onChange: (charges: Charge[]) => void;
  showRefundFeeNotice: boolean;
  canPing: boolean;
  customerEmail: string;
  loading: boolean;
};

const ChargesSection = ({ charges, remainingCharges, onChange, showRefundFeeNotice, canPing, customerEmail, loading }: ChargesSectionProps) => {
  const updateCharge = (id: string, update: Partial<Charge>) =>
    onChange(charges.map((charge) => (charge.id === id ? { ...charge, ...update } : charge)));

  return (
    <section className="stack">
      <header>
        <h3>Charges</h3>
      </header>
      {loading ? (
        <section>
          <div className="text-center">
            <Progress width="2em" />
          </div>
        </section>
      ) : charges.length > 0 ? (
        <>
          {remainingCharges !== null ? (
            <section>
              <div role="status" className="info">
                {`${remainingCharges} ${remainingCharges > 1 ? "charges" : "charge"} remaining`}
              </div>
            </section>
          ) : null}
          {charges.map((charge) => (
            <ChargeRow
              key={charge.id}
              purchase={charge}
              customerEmail={customerEmail}
              onChange={(update) => updateCharge(charge.id, update)}
              showRefundFeeNotice={showRefundFeeNotice}
              canPing={canPing}
            />
          ))}
        </>
      ) : (
        <section>
          <div>No charges yet</div>
        </section>
      )}
    </section>
  );
};

export default ChargesSection;
