import { router } from "@inertiajs/react";
import { format, lightFormat, parseISO } from "date-fns";
import * as React from "react";

import { AnalyticsLayout } from "$app/components/Analytics/AnalyticsLayout";
import { ProductsPopover, type ProductOption } from "$app/components/Analytics/ProductsPopover";
import { useAnalyticsDateRange } from "$app/components/Analytics/useAnalyticsDateRange";
import { ChurnChart, type DataPoint as ChurnChartDataPoint } from "$app/components/Churn/ChurnChart";
import ChurnQuickStats, { type ChurnSummary } from "$app/components/Churn/ChurnQuickStats";
import { DateRangePicker } from "$app/components/DateRangePicker";
import { LoadingSpinner } from "$app/components/LoadingSpinner";
import Placeholder from "$app/components/ui/Placeholder";

import placeholder from "$assets/images/placeholders/sales.png";

type RawChurnMetric = {
  churn_rate: number;
  churned_customers_count: number;
  revenue_lost_cents: number;
};

type RawChurnBucket = {
  by_product: Record<string, RawChurnMetric>;
  total: RawChurnMetric;
};

type ChartPointWithBase = ChurnChartDataPoint & { base: number };

type DateRangeState = {
  from: Date;
  to: Date;
  setFrom: (from: Date) => void;
  setTo: (to: Date) => void;
};

export type ChurnPayload = {
  metadata: {
    start_date: string;
    end_date: string;
    timezone: string;
    products: {
      external_id: string;
      permalink: string;
      name: string;
    }[];
  };
  data: {
    daily: Record<string, RawChurnBucket>;
    monthly: Record<string, RawChurnBucket>;
  };
};

export type ChurnProps = {
  churn: ChurnPayload;
};

const computeBase = (stats?: RawChurnMetric) => {
  if (!stats) return 0;
  if (stats.churn_rate <= 0) return stats.churned_customers_count;
  const base = stats.churned_customers_count / (stats.churn_rate / 100);
  return Number.isFinite(base) ? base : 0;
};

const buildBuckets = (buckets: Record<string, RawChurnBucket>) =>
  Object.entries(buckets).sort(([left], [right]) => parseISO(left).getTime() - parseISO(right).getTime());

const useChurnRangeSync = (
  churn: ChurnPayload,
  dateRange: DateRangeState,
  setIsReloading: (value: boolean) => void,
) => {
  const lastLoadedRange = React.useRef<{ from: string; to: string }>({
    from: churn.metadata.start_date,
    to: churn.metadata.end_date,
  });
  const inFlightRange = React.useRef<{ from: string; to: string } | null>(null);
  const toYMD = React.useCallback((date: Date) => lightFormat(date, "yyyy-MM-dd"), []);

  // Keep the picker/URL in sync with the server-normalized range (e.g., clamped "All time"),
  // and clear in-flight tracking when server data matches what we asked for.
  React.useEffect(() => {
    const serverFrom = parseISO(churn.metadata.start_date);
    const serverTo = parseISO(churn.metadata.end_date);
    if (isNaN(serverFrom.getTime()) || isNaN(serverTo.getTime())) return;

    const pickerMatchesServer =
      serverFrom.getTime() === dateRange.from.getTime() && serverTo.getTime() === dateRange.to.getTime();
    if (!pickerMatchesServer) {
      dateRange.setFrom(serverFrom);
      dateRange.setTo(serverTo < serverFrom ? serverFrom : serverTo);
    }

    const formattedServerFrom = toYMD(serverFrom);
    const formattedServerTo = toYMD(serverTo);
    lastLoadedRange.current = { from: formattedServerFrom, to: formattedServerTo };
    if (
      inFlightRange.current &&
      inFlightRange.current.from === formattedServerFrom &&
      inFlightRange.current.to === formattedServerTo
    ) {
      inFlightRange.current = null;
    }
  }, [churn.metadata.start_date, churn.metadata.end_date, dateRange, toYMD]);

  // Trigger reload when picker changes to a range we haven't requested yet.
  React.useEffect(() => {
    const fromDate = toYMD(dateRange.from);
    const toDate = toYMD(dateRange.to);

    const alreadyLoaded = fromDate === lastLoadedRange.current.from && toDate === lastLoadedRange.current.to;
    const alreadyInFlight = inFlightRange.current?.from === fromDate && inFlightRange.current.to === toDate;
    if (alreadyLoaded || alreadyInFlight) {
      if (alreadyLoaded) inFlightRange.current = null;
      return;
    }

    inFlightRange.current = { from: fromDate, to: toDate };
    setIsReloading(true);
    router.reload({
      only: ["churn"],
      data: { from: fromDate, to: toDate },
      preserveUrl: true,
      onFinish: () => setIsReloading(false),
      onError: () => setIsReloading(false),
    });
  }, [dateRange.from, dateRange.to, setIsReloading, toYMD]);
};

const Churn = ({ churn }: ChurnProps) => {
  const dateRange = useAnalyticsDateRange();
  const [aggregateBy, setAggregateBy] = React.useState<"daily" | "monthly">("daily");
  const [isReloading, setIsReloading] = React.useState(false);

  const allPermalinks = React.useMemo(() => churn.metadata.products.map((product) => product.permalink), [churn]);

  const [products, setProducts] = React.useState<ProductOption[]>(
    churn.metadata.products.map((product) => ({
      id: product.external_id,
      name: product.name,
      unique_permalink: product.permalink,
      alive: true,
      selected: true,
    })),
  );

  React.useEffect(() => {
    setProducts((prev) => {
      const selection = new Map(prev.map((product) => [product.unique_permalink, product.selected]));
      return churn.metadata.products.map((product) => ({
        id: product.external_id,
        name: product.name,
        unique_permalink: product.permalink,
        alive: true,
        selected: selection.get(product.permalink) ?? true,
      }));
    });
  }, [churn.metadata.products]);

  const selectedPermalinks = React.useMemo(
    () => products.filter((product) => product.selected).map((product) => product.unique_permalink),
    [products],
  );

  useChurnRangeSync(churn, dateRange, setIsReloading);

  const dailyBuckets = React.useMemo(() => buildBuckets(churn.data.daily), [churn.data.daily]);
  const monthlyBuckets = React.useMemo(() => buildBuckets(churn.data.monthly), [churn.data.monthly]);

  const aggregateBucket = React.useCallback(
    (bucket: RawChurnBucket) => {
      const usingTotals = selectedPermalinks.length > 0 && selectedPermalinks.length === allPermalinks.length;

      if (usingTotals) {
        const base = computeBase(bucket.total);
        return {
          churnRate: bucket.total.churn_rate,
          churnedCustomers: bucket.total.churned_customers_count,
          revenueLostCents: bucket.total.revenue_lost_cents,
          base,
        };
      }

      let churnedCustomers = 0;
      let revenueLostCents = 0;
      let base = 0;

      selectedPermalinks.forEach((permalink) => {
        const stats = bucket.by_product[permalink];
        if (!stats) return;
        churnedCustomers += stats.churned_customers_count;
        revenueLostCents += stats.revenue_lost_cents;
        base += computeBase(stats);
      });

      const churnRate = base > 0 ? (churnedCustomers / base) * 100 : 0;

      return { churnRate, churnedCustomers, revenueLostCents, base };
    },
    [selectedPermalinks, allPermalinks],
  );

  const chartData = React.useMemo<ChartPointWithBase[]>(() => {
    const buckets = aggregateBy === "daily" ? dailyBuckets : monthlyBuckets;

    return buckets.map(([date, bucket], index) => {
      const metrics = aggregateBucket(bucket);
      const parsedDate = parseISO(date);
      const title = aggregateBy === "monthly" ? format(parsedDate, "MMMM yyyy") : format(parsedDate, "EEEE, MMM d");
      const label =
        index === 0 || index === buckets.length - 1
          ? format(parsedDate, aggregateBy === "monthly" ? "MMM" : "MMM d")
          : "";

      return {
        date,
        label,
        title,
        churnRate: metrics.churnRate,
        churnedCustomers: metrics.churnedCustomers,
        revenueLostCents: metrics.revenueLostCents,
        base: metrics.base,
      };
    });
  }, [aggregateBy, dailyBuckets, monthlyBuckets, aggregateBucket]);

  const summary = React.useMemo<ChurnSummary>(() => {
    if (chartData.length === 0) {
      return { churnRate: 0, churnedCustomers: 0, revenueLostCents: 0 };
    }

    const totals = chartData.reduce(
      (acc, point) => {
        acc.churnedCustomers += point.churnedCustomers;
        acc.revenueLostCents += point.revenueLostCents;
        acc.weightedRate += point.churnRate * (point.base || 0);
        acc.base += point.base || 0;
        return acc;
      },
      { churnedCustomers: 0, revenueLostCents: 0, weightedRate: 0, base: 0 },
    );

    const churnRate = totals.base > 0 ? totals.weightedRate / totals.base : 0;

    return {
      churnRate,
      churnedCustomers: totals.churnedCustomers,
      revenueLostCents: totals.revenueLostCents,
    };
  }, [chartData]);

  const hasProducts = churn.metadata.products.length > 0;

  return (
    <AnalyticsLayout
      selectedTab="churn"
      actions={
        hasProducts ? (
          <>
            <select
              aria-label="Aggregate by"
              onChange={(event) => setAggregateBy(event.target.value === "daily" ? "daily" : "monthly")}
              className="w-auto"
              value={aggregateBy}
            >
              <option value="daily">Daily</option>
              <option value="monthly">Monthly</option>
            </select>
            <ProductsPopover products={products} setProducts={setProducts} />
            <DateRangePicker {...dateRange} />
          </>
        ) : null
      }
    >
      {hasProducts ? (
        <div className="space-y-8 p-4 md:p-8">
          <ChurnQuickStats summary={summary} />
          {isReloading ? (
            <div className="input">
              <LoadingSpinner />
              Loading churn analytics...
            </div>
          ) : chartData.length > 0 ? (
            <ChurnChart data={chartData} />
          ) : (
            <div className="input">No churn data for this date range.</div>
          )}
        </div>
      ) : (
        <div className="p-4 md:p-8">
          <Placeholder>
            <figure>
              <img src={placeholder} />
            </figure>
            <h2>No subscription products yet</h2>
            <p>
              Churn analytics are available for creators with subscription products. Create a membership or subscription
              product to start tracking subscriber retention.
            </p>
            <a href={Routes.help_center_article_path("82-membership-products")} target="_blank" rel="noreferrer">
              Learn more about memberships
            </a>
          </Placeholder>
        </div>
      )}
    </AnalyticsLayout>
  );
};

export default Churn;
