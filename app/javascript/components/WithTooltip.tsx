import * as Tooltip from "@radix-ui/react-tooltip";
import * as React from "react";

import { classNames } from "$app/utils/classNames";

export type Position = "top" | "left" | "bottom" | "right";

export const WithTooltip = ({
  tip,
  children,
  open,
  triggerProps,
  className,
  ...props
}: {
  tip: React.ReactNode | null;
  children: React.ReactNode;
  open?: boolean;
  triggerProps?: Tooltip.TooltipTriggerProps;
} & Tooltip.TooltipContentProps) => {
  if (tip == null) return children;

  return (
    <Tooltip.Root {...(open ? { open } : {})}>
      <Tooltip.Trigger asChild {...triggerProps}>
        <div>{children}</div>
      </Tooltip.Trigger>
      <Tooltip.Portal>
        <Tooltip.Content
          onPointerDownOutside={(e) => e.preventDefault()}
          {...props}
          className={classNames("z-30 w-40 max-w-max rounded-md bg-primary p-3 text-primary-foreground", className)}
        >
          <Tooltip.Arrow className="fill-primary" />
          {tip}
        </Tooltip.Content>
      </Tooltip.Portal>
    </Tooltip.Root>
  );
};
