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
      accent: "border-accent bg-accent/20",
    },
  },
});

const iconNames: Record<Exclude<NonNullable<VariantProps<typeof alertVariants>["variant"]>, "accent">, IconName> = {
  success: "solid-check-circle",
  danger: "x-circle-fill",
  warning: "solid-shield-exclamation",
  info: "info-circle-fill",
};

const iconColorVariants = cva("tailwind-override-icons size-[1lh]", {
  variants: {
    variant: {
      success: "text-success",
      danger: "text-danger",
      warning: "text-warning",
      info: "text-info",
    },
  },
});

export interface AlertProps extends React.HTMLProps<HTMLDivElement> {
  asChild?: boolean;
  children: React.ReactNode;
  variant?: Exclude<VariantProps<typeof alertVariants>["variant"], null>;
}

export const Alert = React.forwardRef<HTMLDivElement, AlertProps>(
  ({ className, children, role = "alert", variant, ...props }, ref) => {
    const hasIcon = React.Children.toArray(children).some(
      (child) => React.isValidElement(child) && child.type === AlertIcon,
    );

    return (
      <div ref={ref} role={role} className={classNames(alertVariants({ variant }), className)} {...props}>
        {!hasIcon && variant && variant !== "accent" ? (
          <Icon name={iconNames[variant]} className={iconColorVariants({ variant })} aria-hidden="true" />
        ) : null}
        {children}
      </div>
    );
  },
);
Alert.displayName = "Alert";

export interface AlertIconProps extends React.HTMLProps<HTMLSpanElement> {
  children?: React.ReactNode;
}

export const AlertIcon = React.forwardRef<HTMLSpanElement, AlertIconProps>(({ children, className, ...props }, ref) => (
  <span ref={ref} className={classNames(className)} {...props}>
    {children}
  </span>
));
AlertIcon.displayName = "AlertIcon";
