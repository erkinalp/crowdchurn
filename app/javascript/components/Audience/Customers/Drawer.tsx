import * as React from "react";

import { CurrencyCode, formatPriceCentsWithCurrencySymbol } from "$app/utils/currency";

import {
  Customer,
  CustomerEmail,
  MissedPost,
  Charge,
  cancelSubscription,
  changeCanContact,
  getCustomerEmails,
  getMissedPosts,
  getProductPurchases,
  markShipped,
  resendPost,
  resendReceipt,
  updateLicense,
  updatePurchase,
  getCharges,
  Discount,
} from "$app/data/customers";
import { assertResponseError } from "$app/utils/request";

import { Button } from "$app/components/Button";
import { Icon } from "$app/components/Icons";
import { Progress } from "$app/components/Progress";
import { useUserAgentInfo } from "$app/components/UserAgent";
import { useRunOnce } from "$app/components/useRunOnce";
import { useClientAlert } from "$app/components/ClientAlertProvider";

import FileRow from "$app/components/Audience/Customers/Sections/FileRow";
import CallSection from "$app/components/Audience/Customers/Sections/Call";
import CommissionSection from "$app/components/Audience/Customers/Sections/Commission";
import PingButton from "$app/components/Audience/Customers/PingButton";
import RefundForm from "$app/components/Audience/Customers/RefundForm";
import AccessSection from "$app/components/Audience/Customers/Sections/Access";
import ChargesSection from "$app/components/Audience/Customers/Sections/Charges";
import LicenseSection from "$app/components/Audience/Customers/Sections/License";
import SubscriptionCancellationSection from "$app/components/Audience/Customers/Sections/SubscriptionCancellation";
import SeatSection from "$app/components/Audience/Customers/Sections/Seat";
import UtmLinkStack from "$app/components/Audience/Customers/UtmLinkStack";
import OptionSection from "$app/components/Audience/Customers/Sections/Option";
import ReviewSection from "$app/components/Audience/Customers/Sections/Review";
import EmailSection from "$app/components/Audience/Customers/Sections/Email";
import TrackingSection from "$app/components/Audience/Customers/Sections/Tracking";
import AddressSection from "$app/components/Audience/Customers/Sections/Address";
import CommissionStatusPill from "$app/components/Audience/Customers/CommissionStatusPill";

import { formatPrice } from "$app/components/Audience/Customers";

const PAGE_SIZE = 10;

const MEMBERSHIP_STATUS_LABELS = {
  alive: "Active",
  cancelled: "Cancelled",
  failed_payment: "Failed payment",
  fixed_subscription_period_ended: "Ended",
  pending_cancellation: "Cancellation pending",
  pending_failure: "Failure pending",
};

const INSTALLMENT_PLAN_STATUS_LABELS = {
  alive: "In progress",
  cancelled: "Cancelled",
  failed_payment: "Payment failed",
  fixed_subscription_period_ended: "Paid in full",
  pending_cancellation: "Cancellation pending",
  pending_failure: "Failure pending",
};

const year = new Date().getFullYear();

const formatDiscount = (discount: Discount, currencyType: CurrencyCode) =>
  discount.type === "fixed"
    ? formatPriceCentsWithCurrencySymbol(currencyType, discount.cents, {
        symbolFormat: "short",
      })
    : `${discount.percents}%`;

type CustomerDrawerProps = {
  customer: Customer;
  onChange: (update: Partial<Customer>) => void;
  onClose: () => void;
  onBack?: () => void;
  countries: string[];
  canPing: boolean;
  showRefundFeeNotice: boolean;
};

const CustomerDrawer = ({
  customer,
  onChange,
  onClose,
  onBack,
  countries,
  canPing,
  showRefundFeeNotice,
}: CustomerDrawerProps) => {
  const userAgentInfo = useUserAgentInfo();

  const [loadingId, setLoadingId] = React.useState<string | null>(null);
  const [missedPosts, setMissedPosts] = React.useState<MissedPost[] | null>(null);
  const [shownMissedPosts, setShownMissedPosts] = React.useState(PAGE_SIZE);
  const [emails, setEmails] = React.useState<CustomerEmail[] | null>(null);
  const [shownEmails, setShownEmails] = React.useState(PAGE_SIZE);
  const sentEmailIds = React.useRef<Set<string>>(new Set());
  const { showAlert } = useClientAlert();
  useRunOnce(() => {
    getMissedPosts(customer.id, customer.email).then(setMissedPosts, (e: unknown) => {
      assertResponseError(e);
      showAlert(e.message, "error");
    });
    getCustomerEmails(customer.id).then(setEmails, (e: unknown) => {
      assertResponseError(e);
      showAlert(e.message, "error");
    });
  });

  const onSend = async (id: string, type: "receipt" | "post") => {
    setLoadingId(id);
    try {
      await (type === "receipt" ? resendReceipt(id) : resendPost(customer.id, id));
      sentEmailIds.current.add(id);
      showAlert(type === "receipt" ? "Receipt resent" : "Email Sent", "success");
    } catch (e) {
      assertResponseError(e);
      showAlert(e.message, "error");
    }
    setLoadingId(null);
  };

  const [productPurchases, setProductPurchases] = React.useState<Customer[]>([]);
  const [selectedProductPurchaseId, setSelectedProductPurchaseId] = React.useState<string | null>(null);
  const selectedProductPurchase = productPurchases.find(({ id }) => id === selectedProductPurchaseId);
  useRunOnce(() => {
    if (customer.is_bundle_purchase)
      void getProductPurchases(customer.id).then(setProductPurchases, (e: unknown) => {
        assertResponseError(e);
        showAlert(e.message, "error");
      });
  });

  const { subscription, commission, license, shipping } = customer;

  const showCharges = subscription || commission;
  const [charges, setCharges] = React.useState<Charge[]>([]);
  const [isLoadingCharges, setIsLoadingCharges] = React.useState(true);
  React.useEffect(() => {
    if (showCharges) {
      setIsLoadingCharges(true);
      getCharges(customer.id, customer.email)
        .then((charges) => {
          setCharges(charges);
        })
        .catch((e: unknown) => {
          assertResponseError(e);
          showAlert(e.message, "error");
        })
        .finally(() => {
          setIsLoadingCharges(false);
        });
    }
  }, [commission?.status]);

  const isCoffee = customer.product.native_type === "coffee";

  if (selectedProductPurchase)
    return (
      <CustomerDrawer
        customer={selectedProductPurchase}
        onChange={(update) =>
          setProductPurchases((prev) => [
            ...prev.filter(({ id }) => id !== selectedProductPurchase.id),
            { ...selectedProductPurchase, ...update },
          ])
        }
        onClose={onClose}
        onBack={() => setSelectedProductPurchaseId(null)}
        countries={countries}
        canPing={canPing}
        showRefundFeeNotice={showRefundFeeNotice}
      />
    );

  const formatDateWithoutTime = (date: Date) =>
    date.toLocaleDateString(userAgentInfo.locale, {
      day: "numeric",
      month: "short",
      year: date.getFullYear() !== year ? "numeric" : undefined,
    });

  return (
    <aside>
      <header>
        {onBack ? (
          <button onClick={onBack} aria-label="Return to bundle">
            <Icon name="arrow-left" style={{ fontSize: "var(--big-icon-size)" }} />
          </button>
        ) : null}
        <h2>{customer.product.name}</h2>
        <button className="close" aria-label="Close" onClick={onClose} />
      </header>
      {commission ? <CommissionStatusPill commission={commission} /> : null}
      {customer.is_additional_contribution ? (
        <div role="status" className="info">
          <div>
            <strong>Additional amount: </strong>
            This is an additional contribution, added to a previous purchase of this product.
          </div>
        </div>
      ) : null}
      {customer.ppp ? (
        <div role="status" className="info">
          <div>
            This customer received a purchasing power parity discount of <b>{customer.ppp.discount}</b> because they are
            located in <b>{customer.ppp.country}</b>.
          </div>
        </div>
      ) : null}
      {customer.giftee_email ? (
        <div role="status" className="info">
          {customer.email} purchased this for {customer.giftee_email}.
        </div>
      ) : null}
      {customer.is_preorder ? (
        <div role="status" className="info">
          <div>
            <strong>Pre-order: </strong>
            This is a pre-order authorization. The customer's card has not been charged yet.
          </div>
        </div>
      ) : null}
      {customer.affiliate && customer.affiliate.type !== "Collaborator" ? (
        <div role="status" className="info">
          <div>
            <strong>Affiliate: </strong>
            An affiliate ({customer.affiliate.email}) helped you make this sale and received {customer.affiliate.amount}
            .
          </div>
        </div>
      ) : null}
      <EmailSection
        label="Email"
        email={customer.email}
        onSave={
          customer.is_existing_user
            ? null
            : (email) =>
                updatePurchase(customer.id, { email }).then(
                  () => {
                    showAlert("Email updated successfully.", "success");
                    onChange({ email });
                    if (productPurchases.length)
                      setProductPurchases((prevProductPurchases) =>
                        prevProductPurchases.map((productPurchase) => ({ ...productPurchase, email })),
                      );
                  },
                  (e: unknown) => {
                    assertResponseError(e);
                    showAlert(e.message, "error");
                  },
                )
        }
        canContact={customer.can_contact}
        onChangeCanContact={(canContact) =>
          changeCanContact(customer.id, canContact).then(
            () => {
              showAlert(
                canContact
                  ? "Your customer will now receive your posts."
                  : "Your customer will no longer receive your posts.",
                "success",
              );
              onChange({ can_contact: canContact });
            },
            (e: unknown) => {
              assertResponseError(e);
              showAlert(e.message, "error");
            },
          )
        }
      />
      {customer.giftee_email ? (
        <EmailSection
          label="Giftee email"
          email={customer.giftee_email}
          onSave={(email) =>
            updatePurchase(customer.id, { giftee_email: email }).then(
              () => {
                showAlert("Email updated successfully.", "success");
                onChange({ giftee_email: email });
              },
              (e: unknown) => {
                assertResponseError(e);
                showAlert(e.message, "error");
              },
            )
          }
        />
      ) : null}
      <section className="stack">
        <h3 className="flex gap-1">
          Order information
          {!subscription && customer.transaction_url_for_seller ? (
            <a href={customer.transaction_url_for_seller} target="_blank" rel="noreferrer" aria-label="Transaction">
              <Icon name="arrow-up-right-square" />
            </a>
          ) : null}
        </h3>
        <div>
          <h5>Customer name</h5>
          {customer.name}
        </div>
        <div>
          <h5>{customer.is_multiseat_license ? "Seats" : "Quantity"}</h5>
          {customer.quantity}
        </div>
        {customer.download_count ? (
          <div>
            <h5>Download count</h5>
            {customer.download_count}
          </div>
        ) : null}
        <div>
          <h5>Price</h5>
          <div>
            {customer.price.cents_before_offer_code > customer.price.cents ? (
              <>
                <s>
                  {formatPrice(
                    customer.price.cents_before_offer_code,
                    customer.price.currency_type,
                    customer.price.recurrence,
                  )}
                </s>{" "}
              </>
            ) : null}
            {formatPrice(
              customer.price.cents - (customer.price.tip_cents ?? 0),
              customer.price.currency_type,
              customer.price.recurrence,
            )}
          </div>
        </div>
        {customer.price.tip_cents ? (
          <div>
            <h5>Tip</h5>
            {formatPrice(customer.price.tip_cents, customer.price.currency_type, customer.price.recurrence)}
          </div>
        ) : null}
        {customer.discount && !customer.upsell ? (
          <div>
            <h5>Discount</h5>
            {customer.discount.code ? (
              <div>
                {formatDiscount(customer.discount, customer.price.currency_type)} off with code{" "}
                <div className="pill small">{customer.discount.code.toUpperCase()}</div>
              </div>
            ) : (
              `${formatDiscount(customer.discount, customer.price.currency_type)} off`
            )}
          </div>
        ) : null}
        {customer.upsell ? (
          <div>
            <h5>Upsell</h5>
            {`${customer.upsell}${
              customer.discount ? ` (${formatDiscount(customer.discount, customer.price.currency_type)} off)` : ""
            }`}
          </div>
        ) : null}
        {subscription?.status ? (
          <div>
            <h5>{subscription.is_installment_plan ? "Installment plan status" : "Membership status"}</h5>
            <div
              style={{
                color:
                  subscription.status === "alive" || subscription.status === "fixed_subscription_period_ended"
                    ? undefined
                    : "var(--red)",
              }}
            >
              {subscription.is_installment_plan
                ? INSTALLMENT_PLAN_STATUS_LABELS[subscription.status]
                : MEMBERSHIP_STATUS_LABELS[subscription.status]}
            </div>
          </div>
        ) : null}
        {customer.referrer ? (
          <div>
            <h5>Referrer</h5>
            {customer.referrer}
          </div>
        ) : null}
        {customer.physical ? (
          <>
            <div>
              <h5>SKU</h5>
              {customer.physical.sku}
            </div>
            <div>
              <h5>Order number</h5>
              {customer.physical.order_number}
            </div>
          </>
        ) : null}
      </section>
      {customer.utm_link ? <UtmLinkStack link={customer.utm_link} showHeader /> : null}
      {customer.review ? (
        <ReviewSection
          review={customer.review}
          purchaseId={customer.id}
          onChange={(updatedReview) => onChange({ review: updatedReview })}
        />
      ) : null}
      {customer.custom_fields.length > 0 ? (
        <section className="stack">
          <header>
            <h3>Information provided</h3>
          </header>
          {customer.custom_fields.map((field, idx) => {
            const content = (
              <section key={idx}>
                <h5>{field.attribute}</h5>
                {field.type === "text" ? (
                  field.value
                ) : (
                  <div role="tree" style={{ marginTop: "var(--spacer-2)" }}>
                    {field.files.map((file) => (
                      <FileRow file={file} key={file.key} />
                    ))}
                  </div>
                )}
              </section>
            );
            return field.type === "file" ? <div key={idx}>{content}</div> : content;
          })}
        </section>
      ) : null}
      {customer.has_options && !isCoffee && customer.product.native_type !== "call" ? (
        <OptionSection
          option={customer.option}
          onChange={(option) => onChange({ option })}
          purchaseId={customer.id}
          productPermalink={customer.product.permalink}
          isSubscription={!!subscription}
          quantity={customer.quantity}
        />
      ) : null}
      {customer.is_bundle_purchase ? (
        <section className="stack">
          <header>
            <h3>Content</h3>
          </header>
          {productPurchases.length > 0 ? (
            productPurchases.map((customer) => (
              <section key={customer.id}>
                <h5>{customer.product.name}</h5>
                <Button onClick={() => setSelectedProductPurchaseId(customer.id)}>Manage</Button>
              </section>
            ))
          ) : (
            <section>
              <div className="text-center">
                <Progress width="2em" />
              </div>
            </section>
          )}
        </section>
      ) : null}
      {license ? (
        <LicenseSection
          license={license}
          onSave={(enabled) =>
            updateLicense(license.id, enabled).then(
              () => {
                showAlert("Changes saved!", "success");
                onChange({ license: { ...license, enabled } });
              },
              (e: unknown) => {
                assertResponseError(e);
                showAlert(e.message, "error");
              },
            )
          }
        />
      ) : null}
      {customer.is_multiseat_license ? (
        <SeatSection
          seats={customer.quantity}
          onSave={(quantity) =>
            updatePurchase(customer.id, { quantity }).then(
              () => {
                showAlert("Successfully updated seats!", "success");
                onChange({ quantity });
              },
              (e: unknown) => {
                assertResponseError(e);
                showAlert(e.message, "error");
              },
            )
          }
        />
      ) : null}
      {shipping ? (
        <>
          <TrackingSection
            tracking={shipping.tracking}
            onMarkShipped={(url) =>
              markShipped(customer.id, url).then(
                () => {
                  showAlert("Changes saved!", "success");
                  onChange({ shipping: { ...shipping, tracking: { url, shipped: true } } });
                },
                (e: unknown) => {
                  assertResponseError(e);
                  showAlert(e.message, "error");
                },
              )
            }
          />
          <AddressSection
            address={shipping.address}
            price={shipping.price}
            onSave={(address) =>
              updatePurchase(customer.id, address).then(
                () => {
                  showAlert("Changes saved!", "success");
                  onChange({ shipping: { ...shipping, address } });
                },
                (e: unknown) => {
                  assertResponseError(e);
                  showAlert(e.message, "error");
                },
              )
            }
            countries={countries}
          />
        </>
      ) : null}
      {customer.call ? <CallSection call={customer.call} onChange={(call) => onChange({ ...customer, call })} /> : null}
      {!showCharges && !customer.refunded && !customer.chargedback && customer.price.cents_refundable > 0 ? (
        <section className="stack">
          <header>
            <h3>Refund</h3>
          </header>
          <section>
            <RefundForm
              purchaseId={customer.id}
              currencyType={customer.price.currency_type}
              amountRefundable={customer.price.cents_refundable}
              showRefundFeeNotice={showRefundFeeNotice}
              paypalRefundExpired={customer.paypal_refund_expired}
              modalTitle="Purchase refund"
              modalText="Would you like to confirm this purchase refund?"
              onChange={(amountRefundable) =>
                onChange({
                  price: { ...customer.price, cents_refundable: amountRefundable },
                  refunded: amountRefundable === 0,
                  partially_refunded: amountRefundable > 0 && amountRefundable < customer.price.cents_refundable,
                })
              }
            />
          </section>
        </section>
      ) : null}
      {subscription?.status === "alive" ? (
        <SubscriptionCancellationSection
          isInstallmentPlan={subscription.is_installment_plan}
          onCancel={() =>
            void cancelSubscription(subscription.id).then(
              () => {
                showAlert("Changes saved!", "success");
                onChange({ subscription: { ...subscription, status: "pending_cancellation" } });
              },
              (e: unknown) => {
                assertResponseError(e);
                showAlert(e.message, "error");
              },
            )
          }
        />
      ) : null}
      {canPing && !subscription ? (
        <section className="stack">
          <div>
            <PingButton purchaseId={customer.id} />
          </div>
        </section>
      ) : null}
      {customer.is_access_revoked !== null && !isCoffee && !commission ? (
        <AccessSection
          purchaseId={customer.id}
          onChange={(isAccessRevoked) => onChange({ is_access_revoked: isAccessRevoked })}
          isAccessRevoked={customer.is_access_revoked}
        />
      ) : null}
      {showCharges ? (
        <ChargesSection
          charges={charges}
          remainingCharges={subscription?.remaining_charges ?? null}
          onChange={setCharges}
          showRefundFeeNotice={showRefundFeeNotice}
          canPing={canPing}
          customerEmail={customer.email}
          loading={isLoadingCharges}
        />
      ) : null}
      {commission ? (
        <CommissionSection commission={commission} onChange={(commission) => onChange({ commission })} />
      ) : null}
      {missedPosts?.length !== 0 ? (
        <section className="stack">
          <header>
            <h3>Send missed posts</h3>
          </header>
          {missedPosts ? (
            <>
              {missedPosts.slice(0, shownMissedPosts).map((post) => (
                <section key={post.id}>
                  <div>
                    <h5>
                      <a href={post.url} target="_blank" rel="noreferrer">
                        {post.name}
                      </a>
                    </h5>
                    <small>{`Originally sent on ${formatDateWithoutTime(new Date(post.published_at))}`}</small>
                  </div>
                  <Button
                    color="primary"
                    disabled={!!loadingId || sentEmailIds.current.has(post.id)}
                    onClick={() => void onSend(post.id, "post")}
                  >
                    {sentEmailIds.current.has(post.id) ? "Sent" : loadingId === post.id ? "Sending...." : "Send"}
                  </Button>
                </section>
              ))}
              {shownMissedPosts < missedPosts.length ? (
                <section>
                  <Button
                    onClick={() => setShownMissedPosts((prevShownMissedPosts) => prevShownMissedPosts + PAGE_SIZE)}
                  >
                    Show more
                  </Button>
                </section>
              ) : null}
            </>
          ) : (
            <section>
              <div className="text-center">
                <Progress width="2em" />
              </div>
            </section>
          )}
        </section>
      ) : null}
      {emails?.length !== 0 ? (
        <section className="stack">
          <header>
            <h3>Emails received</h3>
          </header>
          {emails ? (
            <>
              {emails.slice(0, shownEmails).map((email) => (
                <section key={email.id}>
                  <div>
                    <h5>
                      {email.type === "receipt" ? (
                        <a href={email.url} target="_blank" rel="noreferrer">
                          {email.name}
                        </a>
                      ) : (
                        email.name
                      )}
                    </h5>
                    <small>{`${email.state} ${formatDateWithoutTime(new Date(email.state_at))}`}</small>
                  </div>
                  {email.type === "receipt" ? (
                    <Button
                      color="primary"
                      onClick={() => void onSend(email.id, "receipt")}
                      disabled={!!loadingId || sentEmailIds.current.has(email.id)}
                    >
                      {sentEmailIds.current.has(email.id)
                        ? "Receipt resent"
                        : loadingId === email.id
                          ? "Resending receipt..."
                          : "Resend receipt"}
                    </Button>
                  ) : (
                    <Button
                      color="primary"
                      onClick={() => void onSend(email.id, "post")}
                      disabled={!!loadingId || sentEmailIds.current.has(email.id)}
                    >
                      {sentEmailIds.current.has(email.id)
                        ? "Sent"
                        : loadingId === email.id
                          ? "Sending..."
                          : "Resend email"}
                    </Button>
                  )}
                </section>
              ))}
              {shownMissedPosts < emails.length ? (
                <section>
                  <Button onClick={() => setShownEmails((prevShownEmails) => prevShownEmails + PAGE_SIZE)}>
                    Load more
                  </Button>
                </section>
              ) : null}
            </>
          ) : (
            <section>
              <div className="text-center">
                <Progress width="2em" />
              </div>
            </section>
          )}
        </section>
      ) : null}
    </aside>
  );
};

export default CustomerDrawer;
