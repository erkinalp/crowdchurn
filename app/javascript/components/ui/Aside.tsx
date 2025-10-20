import cx from "classnames";
import * as React from "react";

import { Icon } from "$app/components/Icons";

type AsideProps = {
  children: React.ReactNode;
  className?: string;
  ariaLabel?: string;
  onClose?: () => void;
  header?: React.ReactNode;
};

export const Aside = ({ children, className, ariaLabel, onClose, header }: AsideProps) => {
  const classes = cx(
    "overflow-auto bg-filled p-6 gap-4 flex flex-col",
    "relative hidden lg:flex",
    "lg:border-l lg:border-border lg:w-[40vw]",
    className,
  );

  return (
    <aside className={classes} aria-label={ariaLabel}>
      {header ? (
        <header className="flex items-start justify-between gap-4">
          <div className="flex flex-1 items-start justify-between">{header}</div>
          {onClose ? (
            <button type="button" onClick={onClose} aria-label="Close">
              <Icon name="x" />
            </button>
          ) : null}
        </header>
      ) : null}
      {children}
    </aside>
  );
};

type FixedAsideWrapperProps = {
  children: React.ReactNode;
  className?: string;
  showAside?: boolean;
};

export const FixedAsideWrapper = ({ children, className, showAside = true }: FixedAsideWrapperProps) => (
  <div className={cx("flex-1", showAside && "lg:grid lg:grid-cols-[1fr_30vw]", className)}>{children}</div>
);
