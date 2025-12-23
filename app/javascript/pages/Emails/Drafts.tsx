import { InfiniteScroll, router, usePage } from "@inertiajs/react";
import { formatDistanceToNow } from "date-fns";
import React from "react";
import { cast } from "ts-safe-cast";

import { DraftInstallment, getAudienceCount } from "$app/data/installments";
import { useDebouncedSearch } from "$app/hooks/useDebouncedSearch";
import { assertDefined } from "$app/utils/assert";
import { formatStatNumber } from "$app/utils/formatStatNumber";
import { asyncVoid } from "$app/utils/promise";
import { assertResponseError } from "$app/utils/request";

import { Button, NavigationButton } from "$app/components/Button";
import { useCurrentSeller } from "$app/components/CurrentSeller";
import { DeleteEmailModal } from "$app/components/EmailsPage/DeleteEmailModal";
import { EmptyStatePlaceholder } from "$app/components/EmailsPage/EmptyStatePlaceholder";
import { EditEmailButton, EmailsLayout, NewEmailButton } from "$app/components/EmailsPage/Layout";
import { ViewEmailButton } from "$app/components/EmailsPage/ViewEmailButton";
import { Icon } from "$app/components/Icons";
import { Sheet, SheetHeader } from "$app/components/ui/Sheet";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "$app/components/ui/Table";
import { useUserAgentInfo } from "$app/components/UserAgent";

import draftsPlaceholder from "$assets/images/placeholders/draft_posts.png";

type AudienceCounts = Map<string, number | "loading" | "failed">;

const audienceCountValue = (audienceCounts: AudienceCounts, installmentId: string) => {
  const count = audienceCounts.get(installmentId);
  return count === undefined || count === "loading"
    ? null
    : count === "failed"
      ? "--"
      : formatStatNumber({ value: count });
};

type PageProps = {
  installments: DraftInstallment[];
};

export default function EmailsDrafts() {
  const { installments } = cast<PageProps>(usePage().props);
  const currentSeller = assertDefined(useCurrentSeller(), "currentSeller is required");
  const userAgentInfo = useUserAgentInfo();

  const { query, setQuery } = useDebouncedSearch();

  const [audienceCounts, setAudienceCounts] = React.useState<AudienceCounts>(new Map());
  React.useEffect(() => {
    installments.forEach(
      asyncVoid(async ({ external_id }) => {
        if (audienceCounts.has(external_id)) return;
        setAudienceCounts((prev) => new Map(prev).set(external_id, "loading"));
        try {
          const { count } = await getAudienceCount(external_id);
          setAudienceCounts((prev) => new Map(prev).set(external_id, count));
        } catch (e) {
          assertResponseError(e);
          setAudienceCounts((prev) => new Map(prev).set(external_id, "failed"));
        }
      }),
    );
  }, [installments]);

  const [selectedInstallment, setSelectedInstallment] = React.useState<DraftInstallment | null>(null);
  const [installmentToDelete, setInstallmentToDelete] = React.useState<DraftInstallment | null>(null);

  return (
    <EmailsLayout selectedTab="drafts" hasPosts={!!installments.length} query={query} onQueryChange={setQuery}>
      <div className="space-y-4 p-4 md:p-8">
        {installments.length > 0 ? (
          <>
            <InfiniteScroll data="installments" preserveUrl>
              <Table aria-live="polite" aria-label="Drafts">
                <TableHeader>
                  <TableRow>
                    <TableHead>Subject</TableHead>
                    <TableHead>Sent to</TableHead>
                    <TableHead>Audience</TableHead>
                    <TableHead>Last edited</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {installments.map((installment) => (
                    <TableRow
                      key={installment.external_id}
                      selected={installment.external_id === selectedInstallment?.external_id}
                      onClick={() => setSelectedInstallment(installment)}
                    >
                      <TableCell>{installment.name}</TableCell>
                      <TableCell>{installment.recipient_description}</TableCell>
                      <TableCell
                        aria-busy={audienceCountValue(audienceCounts, installment.external_id) === null}
                        className="whitespace-nowrap"
                      >
                        {audienceCountValue(audienceCounts, installment.external_id)}
                      </TableCell>
                      <TableCell className="whitespace-nowrap">
                        {formatDistanceToNow(installment.updated_at)} ago
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </InfiniteScroll>
            {selectedInstallment ? (
              <Sheet open onOpenChange={() => setSelectedInstallment(null)}>
                <SheetHeader>{selectedInstallment.name}</SheetHeader>
                <div className="stack">
                  <div>
                    <h5>Sent to</h5>
                    {selectedInstallment.recipient_description}
                  </div>
                  <div>
                    <h5>Audience</h5>
                    {audienceCountValue(audienceCounts, selectedInstallment.external_id)}
                  </div>
                  <div>
                    <h5>Last edited</h5>
                    {new Date(selectedInstallment.updated_at).toLocaleString(userAgentInfo.locale, {
                      month: "short",
                      day: "numeric",
                      year: "numeric",
                      hour: "numeric",
                      minute: "numeric",
                      timeZone: currentSeller.timeZone.name,
                    })}
                  </div>
                </div>
                <div className="grid grid-flow-col gap-4">
                  {selectedInstallment.send_emails ? <ViewEmailButton installment={selectedInstallment} /> : null}
                  {selectedInstallment.shown_on_profile ? (
                    <NavigationButton href={selectedInstallment.full_url} target="_blank" rel="noopener noreferrer">
                      <Icon name="file-earmark-medical-fill"></Icon>
                      View post
                    </NavigationButton>
                  ) : null}
                </div>
                <div className="grid grid-flow-col gap-4">
                  <NewEmailButton copyFrom={selectedInstallment.external_id} />
                  <EditEmailButton id={selectedInstallment.external_id} />
                  <Button color="danger" onClick={() => setInstallmentToDelete(selectedInstallment)}>
                    Delete
                  </Button>
                </div>
              </Sheet>
            ) : null}
            <DeleteEmailModal
              installment={installmentToDelete}
              onClose={() => setInstallmentToDelete(null)}
              onSuccess={(deleted) => {
                setSelectedInstallment(null);
                router.replaceProp("installments", (current: DraftInstallment[]) =>
                  current.filter((i) => i.external_id !== deleted.external_id),
                );
              }}
            />
          </>
        ) : (
          <EmptyStatePlaceholder
            title="Manage your drafts"
            description="Drafts allow you to save your emails and send whenever you're ready!"
            placeholderImage={draftsPlaceholder}
          />
        )}
      </div>
    </EmailsLayout>
  );
}
