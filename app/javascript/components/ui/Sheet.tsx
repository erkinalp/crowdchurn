import cx from "classnames";
import * as React from "react";

import { Icon } from "$app/components/Icons";

type SheetProps = {
  children: React.ReactNode;
  className?: string;
  ariaLabel?: string;
  onClose?: () => void;
  header?: React.ReactNode;
};

type SheetHeaderProps = {
  children: React.ReactNode;
  className?: string;
  onClose?: () => void;
};

type SheetTitleProps = {
  children: React.ReactNode;
  className?: string;
};

type SheetFooterProps = {
  children: React.ReactNode;
  className?: string;
};

type SheetCloseProps = {
  children: React.ReactNode;
  asChild?: boolean;
  onClick?: () => void;
};

export const Sheet = ({ children, className, ariaLabel, onClose, header }: SheetProps) => {
  const classes = cx(
    "overflow-auto bg-filled p-6 gap-4 flex flex-col",
    "fixed top-0 right-0 bottom-0 z-[var(--z-index-menubar)] w-full",
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
      {onClose && !header ? (
        <button type="button" onClick={onClose} aria-label="Close" className="absolute top-4 right-4">
          <Icon name="x" />
        </button>
      ) : null}
    </aside>
  );
};

export const SheetHeader = ({ children, className, onClose }: SheetHeaderProps) => (
  <header className={cx("flex items-start justify-between gap-4", className)}>
    <div className="flex flex-1 items-start justify-between">{children}</div>
    {onClose ? (
      <button type="button" onClick={onClose} aria-label="Close">
        <Icon name="x" />
      </button>
    ) : null}
  </header>
);

export const SheetTitle = ({ children, className }: SheetTitleProps) => (
  <h2 className={cx("text-singleline", className)}>{children}</h2>
);

export const SheetFooter = ({ children, className }: SheetFooterProps) => (
  <footer className={cx("mt-auto grid auto-cols-fr grid-flow-row gap-4 sm:grid-flow-col", className)}>
    {children}
  </footer>
);

export const SheetClose = ({ children, asChild, onClick }: SheetCloseProps) => {
  if (asChild && React.isValidElement(children)) {
    return React.cloneElement(children, { onClick } as React.HTMLAttributes<HTMLElement>);
  }

  return (
    <button type="button" onClick={onClick}>
      {children}
    </button>
  );
};
