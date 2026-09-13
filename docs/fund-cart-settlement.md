# Fund-cart settlement and historical rollout

## Operational status

**Historical activation is not enabled by this port.** Local reconciliation is available. `FundCart::ReconciliationService.backing_verifier` and `.write_barrier` intentionally default to `nil`. There is no production implementation of these contracts in this tooling. Missing integrations are blockers, not permissions to trust an old counter. Do not configure a verifier that merely returns operator-authored evidence or the original successful Stripe charge response.

Newly created carts activate their empty ledger automatically. `FundCart#activate_ledger!` rejects carts with historical paid sources or balances. Existing carts remain in reconciliation until backing is established. Historical source imports are deliberately narrower than ordinary checkout: seller balance credits, payout history, refunds/disputes, existing ledger history and ambiguous paid items require recovery tooling before activation. There is no force flag and no migration from the aggregate counter.

## Capabilities, amounts and merchant identity

The implemented eligibility route is `operator_stripe_internal_v1`: operator-managed Stripe custody and an internal operator seller payable, in USD. Its currency restriction comes from `FundCart::Eligibility.currency_supported?`, `BalanceTransaction::Amount`'s canonical operator liability contract and the operator payout processors. It is **not** a claim that Stripe cannot hold other currencies. A Stripe charge balance transaction proves a historical credit; it does not establish today's unencumbered balance or that a seller has never been paid out.

| Route                                                                     | Fund-cart status                                                                                                                                                                                            |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Operator Stripe / same custodian / eligible operator seller payable / USD | Core reservation and internal settlement exist; enable only after reversal, custody and rollout acceptance tests pass. Historical import additionally needs current backing and write-barrier integrations. |
| Stripe direct, destination, connected-account transfers                   | Not established by this implementation. No source-account debit, Connect transfer or recovery authority is inferred from connected credentials.                                                             |
| Independent merchants, PayPal, Kill Bill, cryptocurrencies                | No verified fund-cart reservation/settlement/reversal adapter. Reject unsupported funding before charging; retain ordinary checkout.                                                                        |
| Cross-currency or non-USD custody; buyer-presentment mismatch             | No implicit conversion or currency relabeling. Require a future exact conversion and supported custody/payout contract.                                                                                     |

Independent sellers remain independent. Kill Bill credentials, instances and tenants cannot be pooled. Ordinary direct/destination charges, crypto checkout, batch billing/entitlements, product tax classes, buyer currencies and variant rules remain separate from fund-cart eligibility. Unsupported wishlist items need an actionable status; that is not permission to collect unsupported contributions. No fallback to a global merchant or a second charge to the cart owner's card is permitted.

Funding lots preserve source merchant, beneficiary, processor and custody identity. Native amounts/currency/exponent come from confirmed provider evidence; canonical sale amounts/currency/exponent, listed amount/currency and the recorded conversion rate remain distinct. The enabled no-FX route requires exact agreement, not a conversion through floating point. New monetary columns use integral decimal(36,0); JSON evidence uses integer base units. `balance_subunits` is only a compatibility projection, never authorization.

## Accounting and loss policy

- A source contribution remains a sale by the cart owner, with the existing taxes, fees, affiliate obligations, reporting and receipt. Only net proceeds become restricted. A source credit posts `source_custody -net`, `available +net`, dimensioned by source merchant and owner.
- Reservation moves available proceeds into reserved amounts with durable source allocations. A valid destination receipt connects those allocations to the cart owner's actual product purchase and the actual destination seller balance transaction. Settlement credits seller payable, tax, fee and affiliate obligations, rather than inventing a processor charge. Final fulfillment uses ordinary purchase/entitlement behavior.
- An item refund restores original source lots only after destination obligations or externally delivered funds have actually been recovered. A funded destination has no external charge to refund through ordinary processor code.
- A contribution refund/dispute follows the **original source merchant's** provider route and liability. Freeze affected availability and unresolved reservations. Spent contribution shortfalls are a separate cart-owner debt, not negative spendable funds and not an automatic debit of an unrelated destination seller. Authorized recovery can reduce debt; no stored-card charge is implied. Unrecoverable shortfall belongs in that source merchant's loss accounting.
- Compensation is append-only and idempotent. A partial refund requires scoped postings/event keys; a whole-operation `Ledger.reverse!` is not a partial refund implementation.

Reconciliation reports source purchases, all refund records (including reversed failures), purchase- and charge-level disputes, source seller balance transactions, related balances and payout links, item receipts, funding lots, allocations, operations and ledger postings. Any reversal history blocks this first historical importer rather than guessing how much remains. Nonnegative conserved lot fields, balanced ledger operations, available/reserved ledger projections and reserved allocations are checked. A valid original receipt or a balanced ledger alone is not proof of current provider backing.

## Safe local dry run

Run on a controlled local/test copy or an explicitly authorized primary read context. Reports contain financial identifiers; handle stdout as restricted financial evidence, not public logs. Never use a lagging replica to authorize cutover. The default performs no database writes, jobs, external requests, allocation, repair, or projection refresh.

```sh
RAILS_ENV=test DISABLE_SPRING=1 DISABLE_ALTERITY=1 \
  LD_LIBRARY_PATH=/home/ubuntu/.local/lib/x86_64-linux-gnu \
  bundle exec ruby script/fund_cart_reconciliation --cart 123 --dry-run

bundle exec ruby script/fund_cart_reconciliation --help
```

`123` is an example internal cart ID, not an instruction to access any actual customer's cart. Exit 0 means no identified blockers; 2 means blocked; 64 is invalid CLI arguments; 66 is missing cart. An unexpected exception is an error, never successful activation. `--verify-backing` permits read-only provider lookups only through a reviewed server-configured verifier; none ships here. It does not reserve, replenish, transfer, or import money.

`FundCartReconciliationJob.perform_async(cart_id)` is an optional, explicitly enqueued **read-only** local audit. It logs only the cart ID, fingerprint and blockers, not the full financial snapshot. It has no automatic schedule, activation option, or repair retry. The default CLI does not enqueue it.

## Required core integrations before activation

The service has explicit Ruby dependency injection for contract tests and reviewed deployment integration. Neither dependency is accepted from the CLI or deserialized from a report.

### 1. Current backing verifier

`inspect_backing(fund_cart:, snapshot:, fingerprint:)` returns a hash keyed by source purchase ID as a string. It must use primary local accounting plus actual provider balance/payout lookup and an **already enforceable**, exclusive reserve. No payment mutation occurs during this read-only method. A provider charge capture alone is insufficient. The reserve must be uniquely bound to this cart/source and protected against payout, other carts, refunds and other consumers; cross-cart/source/account concurrency belongs to this integration, not the cart row lock. For combined charges, verify every source portion against the complete charge's net obligations; never issue each source a reserve for the whole charge.

For each successful source, return:

- `fund_cart_id`, `source_purchase_id`, `beneficiary_id`, `source_merchant_account_id`, `custody_key`, `payment_id`, `snapshot_fingerprint` exactly matching the reviewed source.
- `currency`, `currency_exponent`, `source_gross_subunits`, `source_net_subunits`, `reserved_subunits` matching exact enabled-route amounts. Integral amounts only; no numeric-string coercion.
- Actual `balance_transaction_id`, `reserve_reference`, `payout_lookup_reference`, `current_balance_reference` identifying auditable evidence, not generated stand-ins.
- `prior_payout_status: "never_paid"`, `current_backing_status: "held"`. These are conclusions of the reviewed provider/accounting implementation, not flags an operator may assert to override evidence. Paid-out funds require a separate authorized recovery/replenishment implementation and cannot pass this importer.
- Integer Unix times `verified_at`, `available_at`, `expires_at`. Evidence must be no older than five minutes, already available, and unexpired again at commit.

The existing `StripeCustody.confirm(lot:)` does not fulfill this contract. It checks an original capture/balance credit, not an exhaustive current reserve/payout history. Do not wire it in as the verifier.

### 2. Durable write barrier and callback handover

`with_paused_writes(fund_cart:) { |pause| ... }` must acquire a durable, exclusive pause before yielding and keep it through transaction commit. `pause.assert_held!` must fail if ownership is lost; inside the database transaction it must be a local fence check, not an external request. `pause.evidence` contains `reference`, an opaque durable `events_through` cursor, and true `legacy_writers_drained`, `new_callbacks_journaled`, `payouts_paused` facts.

This is a required integration, **not an implementation provided here**. A `ledger_state` update, a Redis lease alone, or a high source ID alone is insufficient:

1. Stop new unsupported funding before payment; pause/drain all legacy and new contribution writers, settlement/reversal workers, affected payout writers and item mutation writers. Hold relevant custody reserves against asynchronous provider activity.
2. Durably journal arriving success, refund and dispute callbacks. Do not discard or acknowledge an unrecorded event. Fence all processes, including old deploy workers; make a lost lease abort the transaction.
3. Resolve pre-cutover in-flight purchases. Their source IDs may be below the high-water mark despite a later success event. The importer blocks unresolved source states rather than silently dropping them. A local `failed` status is not proof of terminal provider failure; such sources also block this importer until a future verified terminal-outcome reconciliation is implemented. Only genuinely zero-price, uncharged `not_charged` rows are exempt.
4. Take the verified snapshot, then under the cart lock re-read it. Its SHA-256 must match the reviewed report. Imports, balanced source-credit operations, activation receipt, high-water mark, event cursor and projection commit atomically. Source purchase uniqueness and `source-credit:<purchase_id>` prevent duplicate credits. Nothing schedules destination allocation from the import itself.
5. Release/drain the journal into the new handlers only after the committed handover. Replay old sources by source ID/operation key, never by aggregate increments. Events arriving during the pause need the durable cursor, not just `purchase.id > high_water_mark`. Recovery after a crash must inspect the committed activation operation before releasing any pause/reserve.

`activate!(expected_fingerprint:)` requires the primary writing role, no enclosing database transaction, the same reviewed fingerprint and those integrations. The CLI additionally requires `--activate`, `--expect` and `--acknowledge-cutover`. No cutover command is supplied for copy/paste here, and none was executed during implementation. Replaying the same completed activation returns its operation without another import; a different fingerprint or inactive cart fails. The marker is `reconcile-activate:<cart_id>` with kind `reconciliation_activation`, state `completed`, and JSON receipt; it is never submitted to the ordinary settlement operation worker.

### 3. Existing withdrawable balances and historical spending

The first importer rejects **any** existing source seller credit, even if its balance is currently unpaid. `FundCartFundingLot#spendable?` rejects sources with `purchase_success_balance_id` or seller balance transactions. A future immutable balance-reclassification association, integrated with payout selection and lot spendability, is needed to restrict such proceeds without clearing purchase columns or deleting balance history. Paid/processing/forfeited balances or any payout links require additional provider evidence and authorized recovery. An unpaid state today is not proof there was never a payout.

Legacy purchased items without a valid backed settlement are ambiguous even if a purchase is marked successful. Do not create a receipt retroactively without establishing its actual funding/destination obligations. Duplicate charge references, duplicate seller credits or an unexplained nominal legacy counter block review. The nominal old-counter comparison diagnoses inconsistencies only; imported value always comes from proven **net** source backing. A complete historical item/reversal/replenishment importer is not included.

## Recovery and rollback

Before activation, blocked dry runs change nothing. Resolve evidence gaps through authorized provider/accounting procedures and re-run. Do not delete a paid-out source or a suspicious item to make the report green. Evidence/hold expiry or a changed snapshot requires a new report and review. A transaction failure rolls back local import and activation together; external reserves and the journal stay under the barrier integration's recovery policy until their disposition is known.

After activation or external settlement, preserve lots, allocations, immutable ledger, operation keys, receipts and event cursors. Pause new contributions/allocation using the supported operational gate and keep reconciliation/reversal/fulfillment recovery workers. Do not roll back to legacy counters, clear source associations, manufacture charge IDs, or drop the new tables. Query the original external operation after any timeout; do not replay an uncertain transfer with a new key. Reverse only confirmed completed legs and restore availability only after confirmed recovery.

Run `spec/lib/fund_cart_migration_spec.rb` to verify both fresh migration ordering and upgrades of existing base tables. The settlement migration retains existing balances as legacy records; its rollback is irreversible so accounting history cannot be discarded.

Partial refund requests require an `operation_key`, retained across retries of the same amount. Seller checkout UI supplies this key; API clients must supply it explicitly. A `pending: true` response acknowledges durable work, not a completed refund. Source refunds with uncertain provider outcomes use refund lookup and metadata matching instead of resubmission. Provider-pending proceeds remain unavailable after a partial refund until a subsequent custody lookup confirms availability.

Provider contract tests use controlled responses. No live payment, migration, cutover, deployment or browser test was performed.
