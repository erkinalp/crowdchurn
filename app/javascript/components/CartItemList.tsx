import { Slot } from "@radix-ui/react-slot";
import * as React from "react";

import { classNames } from "$app/utils/classNames";

type BaseProps = {
  children: React.ReactNode;
  className?: string;
} & React.HTMLAttributes<HTMLElement>;

export const CartItemList = ({ children, className, ...props }: BaseProps) => (
  <div role="list" className={classNames("rounded-sm border border-border bg-background", className)} {...props}>
    {children}
  </div>
);

export const CartItem = ({
  className,
  children,
  extra,
  asChild = false,
  ...props
}: BaseProps & { asChild?: boolean; extra?: React.ReactNode }) => {
  const Comp = asChild ? Slot : "div";
  return (
    <Comp role="listitem" className={classNames("border-border not-first:border-t", className)} {...props}>
      <>
        <section className="flex flex-row gap-3 px-3 py-4 sm:gap-5 sm:p-5">{children}</section>
        {extra ? <section className="flex flex-col gap-4 border-border p-4 not-first:border-t">{extra}</section> : null}
      </>
    </Comp>
  );
};

export const CartItemMedia = ({ className, children, ...props }: BaseProps) => (
  <figure
    className={classNames(
      "tailwind-override relative aspect-square h-16 flex-none overflow-hidden rounded-sm border bg-[url('~images/placeholders/product-cover.png')] bg-cover bg-center sm:h-30",
      className,
    )}
    {...props}
  >
    {children}
  </figure>
);

export const CartItemQuantity = ({ className, children, ...props }: BaseProps & { label?: string }) => (
  <div
    className={classNames(
      "absolute top-0 right-0 flex h-5 min-w-5 translate-x-1/2 -translate-y-1/2 items-center justify-center rounded-full border border-primary-foreground bg-primary px-1 text-xs font-normal text-primary-foreground sm:h-6 sm:min-w-6 sm:px-1.5",
      className,
    )}
    {...props}
  >
    <span className="sr-only">Qty: {children}</span>
    <span aria-hidden>{children}</span>
  </div>
);

export const CartItemMain = ({ className, children, ...props }: BaseProps) => (
  <section className={classNames("flex flex-1 flex-col gap-1", className)} {...props}>
    {children}
  </section>
);

export const CartItemTitle = ({
  className,
  children,
  asChild = false,
  ...props
}: BaseProps & { asChild?: boolean }) => {
  const Comp = asChild ? Slot : "h4";
  return (
    <Comp className={classNames("line-clamp-2 text-base font-medium no-underline sm:text-lg", className)} {...props}>
      {children}
    </Comp>
  );
};

export const CartItemFooter = ({ className, children, ...props }: BaseProps) => (
  <footer className={classNames("mt-auto flex flex-col gap-x-4 gap-y-1 sm:flex-wrap", className)} {...props}>
    {children}
  </footer>
);

export const CartItemActions = ({ className, children, ...props }: BaseProps) => (
  <div className={classNames("flex flex-wrap items-stretch gap-3 pt-2", className)} {...props}>
    {children}
  </div>
);

export const CartItemEnd = ({ className, children, ...props }: BaseProps) => (
  <section className={classNames("ml-auto flex flex-col items-end gap-1", className)} {...props}>
    {children}
  </section>
);
