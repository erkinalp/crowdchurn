import { lightFormat } from "date-fns";
import * as React from "react";
import { createCast } from "ts-safe-cast";

import { AudienceDataByDate, fetchAudienceDataByDate } from "$app/data/audience";
import { AbortError } from "$app/utils/request";
import { register } from "$app/utils/serverComponentUtil";

import { AnalyticsLayout } from "$app/components/Analytics/AnalyticsLayout";
import { useAnalyticsDateRange } from "$app/components/Analytics/useAnalyticsDateRange";
import { AudienceChart } from "$app/components/Audience/AudienceChart";
import { AudienceQuickStats } from "$app/components/Audience/AudienceQuickStats";
import { buttonVariants } from "$app/components/Button";
import { DateRangePicker } from "$app/components/DateRangePicker";
import { Icon } from "$app/components/Icons";
import { LoadingSpinner } from "$app/components/LoadingSpinner";
import { Popover, PopoverContent, PopoverTrigger } from "$app/components/Popover";
import { showAlert } from "$app/components/server-components/Alert";
import { ExportSubscribersPopover } from "$app/components/server-components/FollowersPage/ExportSubscribersPopover";
import Placeholder from "$app/components/ui/Placeholder";
import { WithTooltip } from "$app/components/WithTooltip";

import placeholder from "$assets/images/placeholders/audience.png";

const AudiencePage = ({ total_follower_count }: { total_follower_count: number }) => {
  const dateRange = useAnalyticsDateRange();
  const [data, setData] = React.useState<AudienceDataByDate | null>(null);
  const startTime = lightFormat(dateRange.from, "yyyy-MM-dd");
  const endTime = lightFormat(dateRange.to, "yyyy-MM-dd");

  const hasContent = total_follower_count > 0;

  const activeRequest = React.useRef<AbortController | null>(null);
  React.useEffect(() => {
    const loadData = async () => {
      if (!hasContent) return;

      try {
        if (activeRequest.current) activeRequest.current.abort();
        setData(null);
        const request = fetchAudienceDataByDate({ startTime, endTime });
        activeRequest.current = request.abort;
        setData(await request.response);
        activeRequest.current = null;
      } catch (e) {
        if (e instanceof AbortError) return;
        showAlert("Sorry, something went wrong. Please try again.", "error");
      }
    };
    void loadData();
  }, [startTime, endTime]);

  return (
    <AnalyticsLayout
      selectedTab="following"
      actions={
        <>
          <Popover aria-label="Export">
            <PopoverTrigger aria-label="Export">
              <WithTooltip tip="Export" position="bottom">
                <div className={buttonVariants()}>
                  <Icon aria-label="Download" name="download" />
                </div>
              </WithTooltip>
            </PopoverTrigger>
            <PopoverContent>
              <ExportSubscribersPopover />
            </PopoverContent>
          </Popover>
          <DateRangePicker {...dateRange} />
        </>
      }
    >
      {hasContent ? (
        <div className="space-y-8 p-4 md:p-8">
          <AudienceQuickStats totalFollowers={total_follower_count} newFollowers={data?.new_followers ?? null} />
          {data ? (
            <AudienceChart data={data} />
          ) : (
            <div className="input">
              <LoadingSpinner />
              Loading charts...
            </div>
          )}
        </div>
      ) : (
        <div className="p-4 md:p-8">
          <Placeholder>
            <figure>
              <img src={placeholder} />
            </figure>
            <h2>It's quiet. Too quiet.</h2>
            <p>
              You don't have any followers yet. Once you do, you'll see them here, along with powerful data that can
              help you keep your growing audience engaged.
            </p>
            <a href="/help/article/170-audience" target="_blank" rel="noreferrer">
              Learn more
            </a>
          </Placeholder>
        </div>
      )}
    </AnalyticsLayout>
  );
};

export default register({ component: AudiencePage, propParser: createCast() });
