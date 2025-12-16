import { usePage } from "@inertiajs/react";
import React from "react";
import { cast } from "ts-safe-cast";

import {
  deleteInstallment,
  getAudienceCount,
  getScheduledInstallments,
  Pagination,
  ScheduledInstallment,
  previewInstallment,
  SavedInstallment,
} from "$app/data/installments";
import { assertDefined } from "$app/utils/assert";
import { classNames } from "$app/utils/classNames";
import { asyncVoid } from "$app/utils/promise";
import { AbortError, assertResponseError } from "$app/utils/request";
import { formatStatNumber } from "$app/utils/formatStatNumber";

import { Button, NavigationButton } from "$app/components/Button";
import { useCurrentSeller } from "$app/components/CurrentSeller";
import { EditEmailButton, EmailsLayout, NewEmailButton } from "$app/components/EmailsPage/Layout";
import { Icon } from "$app/components/Icons";
import { Modal } from "$app/components/Modal";
import { showAlert } from "$app/components/server-components/Alert";
import { Sheet, SheetHeader } from "$app/components/ui/Sheet";
import { Table, TableBody, TableCaption, TableCell, TableHead, TableHeader, TableRow } from "$app/components/ui/Table";
import Placeholder from "$app/components/ui/Placeholder";
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
  pagination: Pagination;
};

export default function EmailsScheduled() {
  const { installments: initialInstallments, pagination: initialPagination } = cast<PageProps>(usePage().props);
  const [installments, setInstallments] = React.useState<ScheduledInstallment[]>(initialInstallments);
  const [pagination, setPagination] = React.useState<Pagination>(initialPagination);
  const currentSeller = assertDefined(useCurrentSeller(), "currentSeller is required");
  const userAgentInfo = useUserAgentInfo();
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
  const [selectedInstallmentId, setSelectedInstallmentId] = React.useState<string | null>(null);
  const selectedInstallment = selectedInstallmentId
    ? (installments.find((i) => i.external_id === selectedInstallmentId) ?? null)
    : null;
  const [deletingInstallment, setDeletingInstallment] = React.useState<{
    id: string;
    name: string;
    state: "delete-confirmation" | "deleting";
  } | null>(null);
  const [isLoading, setIsLoading] = React.useState(false);

  const activeFetchRequest = React.useRef<{ cancel: () => void } | null>(null);

  const fetchInstallments = async (reset = false) => {
    const nextPage = reset ? 1 : pagination.next;
    if (!nextPage) return;
    setIsLoading(true);
    try {
      activeFetchRequest.current?.cancel();
      const request = getScheduledInstallments({ page: nextPage, query: "" });
      activeFetchRequest.current = request;
      const response = await request.response;
      setInstallments(reset ? response.installments : [...installments, ...response.installments]);
      setPagination(response.pagination);
      activeFetchRequest.current = null;
      setIsLoading(false);
    } catch (e) {
      if (e instanceof AbortError) return;
      activeFetchRequest.current = null;
      setIsLoading(false);
      assertResponseError(e);
      showAlert("Sorry, something went wrong. Please try again.", "error");
    }
  };

  const handleDelete = async () => {
    if (!deletingInstallment) return;
    try {
      setDeletingInstallment({ ...deletingInstallment, state: "deleting" });
      await deleteInstallment(deletingInstallment.id);
      setInstallments(installments.filter((installment) => installment.external_id !== deletingInstallment.id));
      setDeletingInstallment(null);
      showAlert("Email deleted!", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert("Sorry, something went wrong. Please try again.", "error");
    }
  };

  return (
    <EmailsLayout selectedTab="scheduled">
      <div className="space-y-4 p-4 md:p-8">
        {installments.length > 0 ? (
          <>
            {Object.keys(installmentsByDate).map((date) => (
              <Table
                key={date}
                aria-live="polite"
                className={classNames("mb-16", isLoading && "pointer-events-none opacity-50")}
              >
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
                  {installmentsByDate[date]?.map((installment) => (
                    <TableRow
                      key={installment.external_id}
                      aria-selected={installment.external_id === selectedInstallmentId}
                      onClick={() => setSelectedInstallmentId(installment.external_id)}
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
            {pagination.next ? (
              <Button color="primary" disabled={isLoading} onClick={() => void fetchInstallments()}>
                Load more
              </Button>
            ) : null}
            {selectedInstallment ? (
              <Sheet open onOpenChange={() => setSelectedInstallmentId(null)}>
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
                  <Button
                    color="danger"
                    onClick={() =>
                      setDeletingInstallment({
                        id: selectedInstallment.external_id,
                        name: selectedInstallment.name,
                        state: "delete-confirmation",
                      })
                    }
                  >
                    Delete
                  </Button>
                </div>
              </Sheet>
            ) : null}
            {deletingInstallment ? (
              <Modal
                open
                allowClose={deletingInstallment.state === "delete-confirmation"}
                onClose={() => setDeletingInstallment(null)}
                title="Delete email?"
                footer={
                  <>
                    <Button
                      disabled={deletingInstallment.state === "deleting"}
                      onClick={() => setDeletingInstallment(null)}
                    >
                      Cancel
                    </Button>
                    {deletingInstallment.state === "deleting" ? (
                      <Button color="danger" disabled>
                        Deleting...
                      </Button>
                    ) : (
                      <Button color="danger" onClick={() => void handleDelete()}>
                        Delete email
                      </Button>
                    )}
                  </>
                }
              >
                <h4>
                  Are you sure you want to delete the email "{deletingInstallment.name}"? This action cannot be undone.
                </h4>
              </Modal>
            ) : null}
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

const ViewEmailButton = (props: { installment: SavedInstallment }) => {
  const [sendingPreviewEmail, setSendingPreviewEmail] = React.useState(false);

  return (
    <Button
      disabled={sendingPreviewEmail}
      onClick={asyncVoid(async () => {
        setSendingPreviewEmail(true);
        try {
          await previewInstallment(props.installment.external_id);
          showAlert("A preview has been sent to your email.", "success");
        } catch (error) {
          assertResponseError(error);
          showAlert(error.message, "error");
        } finally {
          setSendingPreviewEmail(false);
        }
      })}
    >
      <Icon name="envelope-fill"></Icon>
      {sendingPreviewEmail ? "Sending..." : "View email"}
    </Button>
  );
};

const EmptyStatePlaceholder = ({
  title,
  description,
  placeholderImage,
}: {
  title: string;
  description: string;
  placeholderImage: string;
}) => (
  <Placeholder>
    <figure>
      <img src={placeholderImage} />
    </figure>
    <h2>{title}</h2>
    <p>{description}</p>
    <NewEmailButton />
    <p>
      <a href="/help/article/169-how-to-send-an-update" target="_blank" rel="noreferrer">
        Learn more about emails
      </a>
    </p>
  </Placeholder>
);
