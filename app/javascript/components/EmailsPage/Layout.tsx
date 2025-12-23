import { Link } from "@inertiajs/react";
import cx from "classnames";
import React from "react";

import { Icon } from "$app/components/Icons";
import { Popover } from "$app/components/Popover";
import { PageHeader } from "$app/components/ui/PageHeader";
import { Tab, Tabs } from "$app/components/ui/Tabs";
import { WithTooltip } from "$app/components/WithTooltip";

type InertiaTab = "published" | "scheduled" | "drafts";
type LegacyTab = "subscribers";
export type EmailTab = InertiaTab | LegacyTab;

// Path helpers - use Rails routes for Inertia pages, hardcoded paths for legacy pages
export const emailTabPath = (tab: EmailTab) => {
  switch (tab) {
    case "published":
      return Routes.published_emails_path();
    case "scheduled":
      return Routes.scheduled_emails_path();
    case "drafts":
      return Routes.drafts_emails_path();
    case "subscribers":
      return Routes.followers_path();
  }
};

type LayoutProps = {
  selectedTab: EmailTab;
  children: React.ReactNode;
  hasPosts?: boolean;
  query: string;
  onQueryChange: (query: string) => void;
};

export const EmailsLayout = ({ selectedTab, children, hasPosts, query, onQueryChange }: LayoutProps) => {
  const searchInputRef = React.useRef<HTMLInputElement>(null);
  const [isSearchPopoverOpen, setIsSearchPopoverOpen] = React.useState(false);

  React.useEffect(() => {
    if (isSearchPopoverOpen) searchInputRef.current?.focus();
  }, [isSearchPopoverOpen]);

  return (
    <div>
      <PageHeader
        title="Emails"
        actions={
          <>
            {hasPosts ? (
              <Popover
                open={isSearchPopoverOpen}
                onToggle={setIsSearchPopoverOpen}
                aria-label="Toggle Search"
                trigger={
                  <WithTooltip tip="Search" position="bottom">
                    <div className="button">
                      <Icon name="solid-search" />
                    </div>
                  </WithTooltip>
                }
              >
                <div className="input">
                  <Icon name="solid-search" />
                  <input
                    ref={searchInputRef}
                    type="text"
                    placeholder="Search emails"
                    value={query}
                    onChange={(evt) => onQueryChange(evt.target.value)}
                  />
                </div>
              </Popover>
            ) : null}
            <NewEmailButton />
          </>
        }
      >
        <Tabs>
          {/* Inertia pages - use Inertia Link for SPA navigation */}
          <Tab asChild isSelected={selectedTab === "published"}>
            <Link href={Routes.published_emails_path()}>Published</Link>
          </Tab>
          <Tab asChild isSelected={selectedTab === "scheduled"}>
            <Link href={Routes.scheduled_emails_path()}>Scheduled</Link>
          </Tab>
          <Tab asChild isSelected={selectedTab === "drafts"}>
            <Link href={Routes.drafts_emails_path()}>Drafts</Link>
          </Tab>
          {/* Legacy pages - use regular href for full page reload */}
          <Tab href={Routes.followers_path()} isSelected={selectedTab === "subscribers"}>
            Subscribers
          </Tab>
        </Tabs>
      </PageHeader>
      {children}
    </div>
  );
};

// Auto-detect current path for 'from' query param so the form can redirect back after cancel
export const NewEmailButton = ({ copyFrom }: { copyFrom?: string } = {}) => {
  const params = new URLSearchParams();
  if (copyFrom) params.set("copy_from", copyFrom);
  params.set("from", window.location.pathname);
  const href = `/emails/new?${params.toString()}`;

  return (
    <a className={cx("button", { accent: !copyFrom })} href={href}>
      {copyFrom ? "Duplicate" : "New email"}
    </a>
  );
};

export const EditEmailButton = ({ id }: { id: string }) => {
  const href = `/emails/${id}/edit?from=${encodeURIComponent(window.location.pathname)}`;
  return (
    <a className="button" href={href}>
      Edit
    </a>
  );
};
