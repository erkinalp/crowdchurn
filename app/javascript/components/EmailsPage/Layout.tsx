import { Link } from "@inertiajs/react";
import React from "react";

import { PageHeader } from "$app/components/ui/PageHeader";
import { Tab, Tabs } from "$app/components/ui/Tabs";

// TODO: Add "drafts" tab back once Drafts page is migrated to Inertia
const TABS = ["published", "scheduled", "subscribers"] as const;
export type EmailTab = (typeof TABS)[number];

// Path helpers using Rails routes
export const emailTabPath = (tab: (typeof TABS)[number]) => {
  switch (tab) {
    case "published":
      return Routes.published_emails_path();
    case "scheduled":
      return Routes.scheduled_emails_path();
    case "subscribers":
      return Routes.followers_path();
  }
};

type LayoutProps = {
  selectedTab: EmailTab;
  children: React.ReactNode;
  hideNewButton?: boolean;
};

export const EmailsLayout = ({ selectedTab, children, hideNewButton }: LayoutProps) => {
  return (
    <div>
      <PageHeader title="Emails" actions={!hideNewButton && <NewEmailButton />}>
        <Tabs>
          <Tab asChild isSelected={selectedTab === "published"}>
            <Link href={Routes.published_emails_path()}>Published</Link>
          </Tab>
          <Tab asChild isSelected={selectedTab === "scheduled"}>
            <Link href={Routes.scheduled_emails_path()}>Scheduled</Link>
          </Tab>
          {/* TODO: Add Drafts tab back once Drafts page is migrated to Inertia */}
          <Tab href={Routes.followers_path()} isSelected={false}>
            Subscribers
          </Tab>
        </Tabs>
      </PageHeader>
      {children}
    </div>
  );
};

// Path helpers for server-components (react-router pages)
// TODO: Remove these once all email pages are migrated to Inertia
export const newEmailPath = "/emails/new";
export const editEmailPath = (id: string) => `/emails/${id}/edit`;

// TODO: Update to use Inertia Link once New email page is migrated
export const NewEmailButton = ({ copyFrom }: { copyFrom?: string } = {}) => {
  const href = copyFrom ? `/emails/new?copy_from=${copyFrom}` : "/emails/new";

  return (
    <a className={copyFrom ? "button" : "button accent"} href={href}>
      {copyFrom ? "Duplicate" : "New email"}
    </a>
  );
};

// TODO: Update to use Inertia Link once Edit email page is migrated
export const EditEmailButton = ({ id }: { id: string }) => {
  return (
    <a className="button" href={`/emails/${id}/edit`}>
      Edit
    </a>
  );
};
