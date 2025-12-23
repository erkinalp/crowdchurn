import { InfiniteScroll, router, usePage } from "@inertiajs/react";
import React from "react";
import { cast } from "ts-safe-cast";

import { getAudienceCount, ScheduledInstallment } from "$app/data/installments";
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
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from "$app/components/ui/Table";
import { useUserAgentInfo } from "$app/components/UserAgent";

import scheduledPlaceholder from "$assets/images/placeholders/scheduled_posts.png";

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
  installments: ScheduledInstallment[];
};

export default function EmailsScheduled() {
  const { installments } = cast<PageProps>(usePage().props);
  const currentSeller = assertDefined(useCurrentSeller(), "currentSeller is required");
  const userAgentInfo = useUserAgentInfo();

  const { query, setQuery } = useDebouncedSearch();

  const installmentsByDate = React.useMemo(
    () =>
      installments.reduce<Record<string, ScheduledInstallment[]>>((acc, installment) => {
        const date = new Date(installment.to_be_published_at).toLocaleDateString(userAgentInfo.locale, {
          month: "short",
          day: "numeric",
          year: "numeric",
          timeZone: currentSeller.timeZone.name,
        });
        if (!acc[date]) acc[date] = [];
        acc[date].push(installment);
        return acc;
      }, {}),
    [installments, userAgentInfo.locale, currentSeller.timeZone.name],
  );

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

  const [selectedInstallment, setSelectedInstallment] = React.useState<ScheduledInstallment | null>(null);
  const [installmentToDelete, setInstallmentToDelete] = React.useState<ScheduledInstallment | null>(null);

  return (
    <EmailsLayout selectedTab="scheduled" hasPosts={!!installments.length} query={query} onQueryChange={setQuery}>
      <div className="space-y-4 p-4 md:p-8">
        {installments.length > 0 ? (
          <>
            <InfiniteScroll data="installments" preserveUrl>
              {Object.keys(installmentsByDate).map((date) => (
                <Table key={date} aria-live="polite" className="mb-16">
                  <TableCaption>Scheduled for {date}</TableCaption>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Subject</TableHead>
                      <TableHead>Sent to</TableHead>
                      <TableHead>Audience</TableHead>
                      <TableHead>Delivery Time</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {installmentsByDate[date]?.map((installment: ScheduledInstallment) => (
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
                          {new Date(installment.to_be_published_at).toLocaleTimeString(userAgentInfo.locale, {
                            hour: "numeric",
                            minute: "numeric",
                            timeZone: currentSeller.timeZone.name,
                          })}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              ))}
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
                    <h5>Delivery Time</h5>
                    {new Date(selectedInstallment.to_be_published_at).toLocaleString(userAgentInfo.locale, {
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
                router.replaceProp("installments", (current: ScheduledInstallment[]) =>
                  current.filter((i) => i.external_id !== deleted.external_id),
                );
              }}
            />
          </>
        ) : (
          <EmptyStatePlaceholder
            title="Set it and forget it."
            description="Schedule an email to be sent exactly when you want."
            placeholderImage={scheduledPlaceholder}
          />
        )}
      </div>
    </EmailsLayout>
  );
}
