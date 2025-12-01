import { Slot, Slottable } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import * as React from "react";

import { classNames } from "$app/utils/classNames";

import { Icon } from "$app/components/Icons";

const alertVariants = cva("grid items-start gap-2 rounded border border-border p-3 grid-cols-[auto_1fr]", {
  variants: {
    variant: {
      success: "border-success bg-success/20",
      danger: "border-danger bg-danger/20",
      warning: "border-warning bg-warning/20",
      info: "border-info bg-info/20",
      pink: "border-pink bg-pink/20",
    },
  },
});

const iconNames: Record<NonNullable<VariantProps<typeof alertVariants>["variant"]>, IconName> = {
  success: "solid-check-circle",
  danger: "x-circle-fill",
  warning: "solid-shield-exclamation",
  info: "info-circle-fill",
  pink: "info-circle-fill",
};

const iconColorVariants = cva("tailwind-override-icons size-[1lh]", {
  variants: {
    variant: {
      success: "text-success",
      danger: "text-danger",
      warning: "text-warning",
      info: "text-info",
      pink: "text-pink",
    },
  },
});

const AlertContext = React.createContext<Exclude<VariantProps<typeof alertVariants>["variant"], null>>(undefined);

export interface AlertProps
  extends React.HTMLProps<HTMLDivElement>,
    Omit<VariantProps<typeof alertVariants>, "variant"> {
  asChild?: boolean;
  children: React.ReactNode;
  role?: "alert" | "status";
  variant?: Exclude<VariantProps<typeof alertVariants>["variant"], null>;
}

export const Alert = React.forwardRef<HTMLDivElement, AlertProps>(
  ({ asChild, className, children, role = "alert", variant, ...props }, ref) => {
    const hasIcon = React.Children.toArray(children).some(
      (child) => React.isValidElement(child) && child.type === AlertIcon,
    );

    const Component = asChild ? Slot : "div";

    return (
      <AlertContext.Provider value={variant}>
        <Component ref={ref} role={role} className={classNames(alertVariants({ variant }), className)} {...props}>
          {!hasIcon && variant ? (
            <Icon name={iconNames[variant]} className={iconColorVariants({ variant })} aria-hidden="true" />
          ) : null}
          {asChild ? <Slottable>{children}</Slottable> : children}
        </Component>
      </AlertContext.Provider>
    );
  },
);
Alert.displayName = "Alert";

export interface AlertIconProps extends React.HTMLProps<HTMLSpanElement> {
  children?: React.ReactNode;
  asChild?: boolean;
}

export const AlertIcon = React.forwardRef<HTMLSpanElement, AlertIconProps>(
  ({ children, asChild, className, ...props }, ref) => {
    const variant = React.useContext(AlertContext);
    const Component = asChild ? Slot : "span";

    if (children) {
      return (
        <Component ref={ref} className={classNames(className)} {...props}>
          {children}
        </Component>
      );
    }

    if (!variant) {
      return null;
    }

    return (
      <Icon
        name={iconNames[variant]}
        className={classNames(iconColorVariants({ variant }), className)}
        aria-hidden="true"
      />
    );
  },
);
AlertIcon.displayName = "AlertIcon";
