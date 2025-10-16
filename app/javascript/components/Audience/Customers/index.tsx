import { lightFormat, subMonths } from "date-fns";
import { format } from "date-fns-tz";
import * as React from "react";

import {
  Customer,
  Query,
  SortKey,
  getPagedCustomers,
} from "$app/data/customers";
import {
  CurrencyCode,
  formatPriceCentsWithCurrencySymbol,
} from "$app/utils/currency";
import { asyncVoid } from "$app/utils/promise";
import { RecurrenceId, recurrenceLabels } from "$app/utils/recurringPricing";
import { AbortError, assertResponseError } from "$app/utils/request";

import { NavigationButton } from "$app/components/Button";
import { useCurrentSeller } from "$app/components/CurrentSeller";
import { DateInput } from "$app/components/DateInput";
import { DateRangePicker } from "$app/components/DateRangePicker";
import { Icon } from "$app/components/Icons";
import { Pagination, PaginationProps } from "$app/components/Pagination";
import { Popover } from "$app/components/Popover";
import { PriceInput } from "$app/components/PriceInput";
import { Toggle } from "$app/components/Toggle";
import { PageHeader } from "$app/components/ui/PageHeader";
import Placeholder from "$app/components/ui/Placeholder";
import { useDebouncedCallback } from "$app/components/useDebouncedCallback";
import { useOnChange } from "$app/components/useOnChange";
import { useUserAgentInfo } from "$app/components/UserAgent";
import { useSortingTableDriver } from "$app/components/useSortingTableDriver";
import { WithTooltip } from "$app/components/WithTooltip";
import { useClientAlert } from "$app/components/ClientAlertProvider";

import UtmLinkStack from "$app/components/Audience/Customers/UtmLinkStack";
import CustomerDrawer from "$app/components/Audience/Customers/Drawer";
import ProductSelect from "$app/components/Audience/Customers/ProductSelect";
import placeholder from "$assets/images/placeholders/customers.png";

export type Item = { type: "product"; id: string } | { type: "variant"; id: string; productId: string };
export type Product = { id: string; name: string; variants: { id: string; name: string }[] };

export type CustomerPageProps = {
  customers: Customer[];
  pagination: PaginationProps | null;
  product_id: string | null;
  products: Product[];
  count: number;
  currency_type: CurrencyCode;
  countries: string[];
  can_ping: boolean;
  show_refund_fee_notice: boolean;
};

const year = new Date().getFullYear();

export const formatPrice = (priceCents: number, currencyType: CurrencyCode, recurrence?: RecurrenceId | null) =>
  `${formatPriceCentsWithCurrencySymbol(currencyType, priceCents, { symbolFormat: "long" })}${
    recurrence ? ` ${recurrenceLabels[recurrence]}` : ""
  }`;

const CustomersPage = ({
  product_id,
  products,
  currency_type,
  countries,
  can_ping,
  show_refund_fee_notice,
  ...initialState
}: CustomerPageProps) => {
  const currentSeller = useCurrentSeller();
  const userAgentInfo = useUserAgentInfo();

  const [{ customers, pagination, count }, setState] = React.useState<{
    customers: Customer[];
    pagination: PaginationProps | null;
    count: number;
  }>(initialState);
  const updateCustomer = (id: string, update: Partial<Customer>) =>
    setState((prev) => ({
      ...prev,
      customers: prev.customers.map((customer) => (customer.id === id ? { ...customer, ...update } : customer)),
    }));
  const [isLoading, setIsLoading] = React.useState(false);
  const activeRequest = React.useRef<{ cancel: () => void } | null>(null);

  const uid = React.useId();

  const [includedItems, setIncludedItems] = React.useState<Item[]>(
    product_id ? [{ type: "product", id: product_id }] : [],
  );
  const [excludedItems, setExcludedItems] = React.useState<Item[]>([]);

  const [query, setQuery] = React.useState<Query>(() => {
    const urlParams = typeof window !== "undefined" ? new URLSearchParams(window.location.search) : null;
    return {
      page: 1,
      query: urlParams?.get("query") ?? urlParams?.get("email") ?? null,
      sort: { key: "created_at", direction: "desc" },
      products: [],
      variants: [],
      excludedProducts: [],
      excludedVariants: [],
      minimumAmount: null,
      maximumAmount: null,
      createdAfter: null,
      createdBefore: null,
      country: null,
      activeCustomersOnly: false,
    };
  });
  const updateQuery = (update: Partial<Query>) => setQuery((prevQuery) => ({ ...prevQuery, ...update }));
  const {
    query: searchQuery,
    sort,
    minimumAmount,
    maximumAmount,
    createdAfter,
    createdBefore,
    country,
    activeCustomersOnly,
  } = query;

  const [selectedCustomerId, setSelectedCustomerId] = React.useState<string | null>(null);
  const selectedCustomer = customers.find(({ id }) => id === selectedCustomerId);

  const thProps = useSortingTableDriver<SortKey>(sort, (sort) => updateQuery({ sort }));

  const includedProductIds = includedItems.filter(({ type }) => type === "product").map(({ id }) => id);
  const includedVariantIds = includedItems.filter(({ type }) => type === "variant").map(({ id }) => id);

  const { showAlert } = useClientAlert();

  const loadCustomers = async (page: number) => {
    activeRequest.current?.cancel();
    setIsLoading(true);
    const request = getPagedCustomers({
      ...query,
      page,
      products: includedProductIds,
      variants: includedVariantIds,
      excludedProducts: excludedItems.filter(({ type }) => type === "product").map(({ id }) => id),
      excludedVariants: excludedItems.filter(({ type }) => type === "variant").map(({ id }) => id),
    });
    activeRequest.current = request;

    try {
      setState(await request.response);
    } catch (e) {
      if (e instanceof AbortError) return;
      assertResponseError(e);
      showAlert(e.message, "error");
    }

    setIsLoading(false);
    activeRequest.current = null;
  };

  const reloadCustomers = async () => loadCustomers(1);

  const searchInputRef = React.useRef<HTMLInputElement>(null);

  const debouncedReloadCustomers = useDebouncedCallback(asyncVoid(reloadCustomers), 300);
  React.useEffect(() => {
    if (searchQuery !== null) debouncedReloadCustomers();
  }, [searchQuery]);

  useOnChange(() => {
    debouncedReloadCustomers();
  }, [query, includedItems, excludedItems]);

  const [from, setFrom] = React.useState(subMonths(new Date(), 1));
  const [to, setTo] = React.useState(new Date());

  const exportNames = React.useMemo(
    () =>
      includedItems.length > 0
        ? includedItems
            .flatMap(({ type, id }) => {
              if (type === "product") {
                return products.find((product) => id === product.id)?.name ?? [];
              }
              const product = products.find(({ variants }) => variants.some((variant) => variant.id === id));
              const variant = product?.variants.find((variant) => variant.id === id);
              if (!product || !variant) return [];
              return `${product.name} - ${variant.name}`;
            })
            .join(", ")
        : null,
    [includedItems, products],
  );

  if (!currentSeller) return null;
  const timeZoneAbbreviation = format(new Date(), "z", { timeZone: currentSeller.timeZone.name });

  return (
    <div className="h-full">
      <PageHeader
        title="Sales"
        actions={
          <>
            <Popover
              aria-label="Search"
              onToggle={() => searchInputRef.current?.focus()}
              trigger={
                <WithTooltip tip="Search">
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
                  placeholder="Search sales"
                  value={searchQuery ?? ""}
                  onChange={(evt) => updateQuery({ query: evt.target.value })}
                  autoFocus
                />
              </div>
            </Popover>
            <Popover
              aria-label="Filter"
              trigger={
                <WithTooltip tip="Filter">
                  <div className="button">
                    <Icon name="filter" />
                  </div>
                </WithTooltip>
              }
            >
              <div className="stack" style={{ width: "35rem" }}>
                <div>
                  <ProductSelect
                    products={products.filter(
                      (product) => !excludedItems.find((excludedItem) => product.id === excludedItem.id),
                    )}
                    label="Customers who bought"
                    items={includedItems}
                    setItems={setIncludedItems}
                  />
                </div>
                <div>
                  <ProductSelect
                    products={products.filter(
                      (product) => !includedItems.find((includedItem) => product.id === includedItem.id),
                    )}
                    label="Customers who have not bought"
                    items={excludedItems}
                    setItems={setExcludedItems}
                  />
                </div>
                <div>
                  <div
                    style={{
                      display: "grid",
                      gap: "var(--spacer-4)",
                      gridTemplateColumns: "repeat(auto-fit, minmax(var(--dynamic-grid), 1fr))",
                    }}
                  >
                    <fieldset>
                      <label htmlFor={`${uid}-minimum-amount`}>Paid more than</label>
                      <PriceInput
                        id={`${uid}-minimum-amount`}
                        currencyCode={currency_type}
                        cents={minimumAmount}
                        onChange={(minimumAmount) => updateQuery({ minimumAmount })}
                        placeholder="0"
                      />
                    </fieldset>
                    <fieldset>
                      <label htmlFor={`${uid}-maximum-amount`}>Paid less than</label>
                      <PriceInput
                        id={`${uid}-maximum-amount`}
                        currencyCode={currency_type}
                        cents={maximumAmount}
                        onChange={(maximumAmount) => updateQuery({ maximumAmount })}
                        placeholder="0"
                      />
                    </fieldset>
                  </div>
                </div>
                <div>
                  <div
                    style={{
                      display: "grid",
                      gap: "var(--spacer-4)",
                      gridTemplateColumns: "repeat(auto-fit, minmax(var(--dynamic-grid), 1fr))",
                    }}
                  >
                    <fieldset>
                      <label htmlFor={`${uid}-after-date`}>After</label>
                      <DateInput
                        id={`${uid}-after-date`}
                        value={createdAfter}
                        onChange={(createdAfter) => updateQuery({ createdAfter })}
                        max={createdBefore || undefined}
                      />
                      <small suppressHydrationWarning>{`00:00  ${timeZoneAbbreviation}`}</small>
                    </fieldset>
                    <fieldset>
                      <label htmlFor={`${uid}-before-date`}>Before</label>
                      <DateInput
                        id={`${uid}-before-date`}
                        value={createdBefore}
                        onChange={(createdBefore) => updateQuery({ createdBefore })}
                        min={createdAfter || undefined}
                      />
                      <small suppressHydrationWarning>{`11:59 ${timeZoneAbbreviation}`}</small>
                    </fieldset>
                  </div>
                </div>
                <div>
                  <fieldset>
                    <label htmlFor={`${uid}-country`}>From</label>
                    <select
                      id={`${uid}-country`}
                      value={country ?? "Anywhere"}
                      onChange={(evt) =>
                        updateQuery({ country: evt.target.value === "Anywhere" ? null : evt.target.value })
                      }
                    >
                      <option>Anywhere</option>
                      {countries.map((country) => (
                        <option value={country} key={country}>
                          {country}
                        </option>
                      ))}
                    </select>
                  </fieldset>
                </div>
                <div>
                  <h4>
                    <label htmlFor={`${uid}-active-customers-only`}>Show active customers only</label>
                  </h4>
                  <Toggle
                    id={`${uid}-active-customers-only`}
                    value={activeCustomersOnly}
                    onChange={(activeCustomersOnly) => updateQuery({ activeCustomersOnly })}
                  />
                </div>
              </div>
            </Popover>
            <Popover
              aria-label="Export"
              trigger={
                <WithTooltip tip="Export">
                  <div className="button">
                    <Icon name="download" />
                  </div>
                </WithTooltip>
              }
            >
              <div className="paragraphs">
                <h3>Download sales as CSV</h3>
                <div>
                  {exportNames
                    ? `This will download sales of '${exportNames}' as a CSV, with each purchase on its own row.`
                    : "This will download a CSV with each purchase on its own row."}
                </div>
                <DateRangePicker from={from} to={to} setFrom={setFrom} setTo={setTo} />
                <NavigationButton
                  color="primary"
                  href={Routes.export_purchases_path({
                    format: "csv",
                    start_time: lightFormat(from, "yyyy-MM-dd"),
                    end_time: lightFormat(to, "yyyy-MM-dd"),
                    product_ids: includedProductIds,
                    variant_ids: includedVariantIds,
                  })}
                >
                  Download
                </NavigationButton>
                {count > 2000 && (
                  <div className="mt-2 text-sm text-gray-600">
                    Exports over 2,000 rows will be processed in the background and emailed to you.
                  </div>
                )}
              </div>
            </Popover>
          </>
        }
      />
      <section className="p-4 md:p-8">
        {customers.length > 0 ? (
          <section className="paragraphs">
            <table aria-live="polite" aria-busy={isLoading}>
              <caption>{`All sales (${count})`}</caption>
              <thead>
                <tr>
                  <th>Email</th>
                  <th>Name</th>
                  <th>Product</th>
                  <th {...thProps("created_at")}>Purchase Date</th>
                  <th {...thProps("price_cents")}>Price</th>
                </tr>
              </thead>
              <tbody>
                {customers.map((customer) => {
                  const price = formatPrice(
                    customer.price.cents,
                    customer.price.currency_type,
                    customer.price.recurrence,
                  );
                  const createdAt = new Date(customer.created_at);
                  return (
                    <tr
                      key={customer.id}
                      aria-selected={selectedCustomerId === customer.id}
                      onClick={() => setSelectedCustomerId(customer.id)}
                    >
                      <td>
                        {customer.shipping && !customer.shipping.tracking.shipped ? (
                          <WithTooltip tip="Not Shipped">
                            <Icon name="truck" style={{ marginRight: "var(--spacer-2)" }} aria-label="Not Shipped" />
                          </WithTooltip>
                        ) : null}
                        {customer.email.length <= 30 ? customer.email : `${customer.email.slice(0, 27)}...`}
                      </td>
                      <td>{customer.name}</td>
                      <td>
                        {customer.product.name}
                        {customer.subscription?.is_installment_plan ? (
                          <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                            Installments
                          </span>
                        ) : null}
                        {customer.is_bundle_purchase ? (
                          <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                            Bundle
                          </span>
                        ) : null}
                        {customer.subscription ? (
                          !customer.subscription.is_installment_plan && customer.subscription.status !== "alive" ? (
                            <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                              Inactive
                            </span>
                          ) : null
                        ) : (
                          <>
                            {customer.partially_refunded ? (
                              <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                                Partially refunded
                              </span>
                            ) : null}
                            {customer.refunded ? (
                              <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                                Refunded
                              </span>
                            ) : null}
                            {customer.chargedback ? (
                              <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                                Chargedback
                              </span>
                            ) : null}
                          </>
                        )}
                        {customer.utm_link ? (
                          <div className="has-tooltip" aria-describedby={`utm-link-${customer.id}`}>
                            <span className="pill small" style={{ marginLeft: "var(--spacer-2)" }}>
                              UTM
                            </span>
                            <div
                              role="tooltip"
                              id={`utm-link-${customer.id}`}
                              style={{ padding: 0, width: "20rem" }}
                              onClick={(e) => e.stopPropagation()}
                            >
                              <UtmLinkStack link={customer.utm_link} showHeader={false} />
                            </div>
                          </div>
                        ) : null}
                      </td>
                      <td>
                        {createdAt.toLocaleDateString(userAgentInfo.locale, {
                          day: "numeric",
                          month: "short",
                          year: createdAt.getFullYear() !== year ? "numeric" : undefined,
                          hour: "numeric",
                          minute: "numeric",
                          hour12: true,
                        })}
                      </td>
                      <td>
                        {customer.transaction_url_for_seller ? (
                          <a href={customer.transaction_url_for_seller}>{price}</a>
                        ) : (
                          price
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            {pagination && pagination.pages > 1 ? (
              <Pagination onChangePage={asyncVoid(loadCustomers)} pagination={pagination} />
            ) : null}
          </section>
        ) : (
          <Placeholder>
            <figure>
              <img src={placeholder} />
            </figure>
            {searchQuery !== null ? (
              <h2>No sales found</h2>
            ) : (
              <>
                <h2>Manage all of your sales in one place.</h2>
                Every time a new customer purchases a product from your Gumroad, their email address and other details
                are added here.
                <div>
                  <NavigationButton color="accent" href={Routes.new_product_path()}>
                    Start selling today
                  </NavigationButton>
                </div>
                <p>
                  or{" "}
                  <a href="/help/article/268-customer-dashboard" target="_blank" rel="noreferrer">
                    learn more about the audience dashboard
                  </a>
                </p>
              </>
            )}
          </Placeholder>
        )}
        {selectedCustomer ? (
          <CustomerDrawer
            key={selectedCustomerId}
            customer={selectedCustomer}
            onChange={(update) => updateCustomer(selectedCustomer.id, update)}
            onClose={() => setSelectedCustomerId(null)}
            countries={countries}
            canPing={can_ping}
            showRefundFeeNotice={show_refund_fee_notice}
          />
        ) : null}
      </section>
    </div>
  );
};

export default CustomersPage;
