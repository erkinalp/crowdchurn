import * as React from "react";
import { createCast } from "ts-safe-cast";

import { classNames } from "$app/utils/classNames";
import { register } from "$app/utils/serverComponentUtil";

import { buttonVariants } from "$app/components/Button";
import { Icon } from "$app/components/Icons";
import { Popover, PopoverContent, PopoverTrigger } from "$app/components/Popover";
import { WithTooltip } from "$app/components/WithTooltip";

type Props = { contentHTML: string };

export const FilterPopover = ({ contentHTML }: Props) => (
  <Popover aria-label="Filter">
    <PopoverTrigger>
      <WithTooltip tip="Filter" position="bottom">
        <div className={classNames(buttonVariants(), "js-toggle-filter-list")}>
          <Icon name="filter" />
        </div>
      </WithTooltip>
    </PopoverTrigger>
    <PopoverContent>
      <div
        className="js-filter-list customer-popover--filter filter-box"
        dangerouslySetInnerHTML={{ __html: contentHTML }}
        suppressHydrationWarning
        style={{ margin: "calc(-1 * var(--spacer-4) - var(--border-width))", maxWidth: "unset" }}
      />
    </PopoverContent>
  </Popover>
);

export default register({ component: FilterPopover, propParser: createCast() });
