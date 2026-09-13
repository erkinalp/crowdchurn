# Historical email engagement migration

Runtime reads and writes use `EmailEngagementDynamoStore`, not Mongoid. This standalone tool imports historical Mongo/FerretDB documents into the upstream DynamoDB item model. It never invokes live `record_open`/`record_click`, mailers, workers, or MySQL callbacks. The `mongo` gem must be declared `require: false`; only the source adapter's `connect` method requires it. No Rails boot or application data services are needed to run the tool or its isolated specs.

## Safety contract

**Do not import into a live or previously used table. Concurrent target writes are unsupported.** Create a dedicated empty table with string `pk` (HASH) and `sk` (RANGE), and an operator-approved distinct name such as `migration-20260912-email_engagement`. The table must be in the runtime account/region and use the desired production durability, encryption, backup and capacity configuration. The tool does not create or delete tables.

Use an isolated restored Mongo/FerretDB snapshot, with read-only credentials and no writers. Both `creator_email_open_events` and `creator_email_click_events` collections must exist, even if empty. Use source indexes on `installment_id`; a compound `(installment_id, _id)` index is recommended for large partitions. Pagination uses installment IDs and source `_id` keys, not offsets or server cursors held across checkpoints. Source `_id` values must be the legacy Mongoid BSON ObjectIds; mixed/string/null IDs are rejected because Mongo range queries are type-bracketed and could otherwise skip rows. Memory is bounded by the largest installment, not the entire database. Rehearse the largest installment to size migration memory; no source rows are silently dropped on memory/error conditions.

Use separate migration credentials and IAM/resource/network policies to **deny application workers/webhooks access to the staged table until release**. The flags are explicit operator attestations, not a substitute for that isolation. `--active-table` is mandatory and must be the real current runtime table, even when the old deployment still writes Mongo. The CLI refuses that table. An absent migration marker requires an entirely empty target; a foreign marker or differing existing item aborts. Every data write is conditional insert-only. No command overwrites an existing historical/live data item, deletes data, or adds counters. Retain the migration marker and item ownership attributes after cutover.

The marker in the target records the run ID, immutable snapshot ID, format version, state, and last fully written installment. Resume with exactly the same identifiers and unchanged source snapshot; use one migration process at a time. A transient failure is retried with bounded backoff. A crash or lost acknowledgement before checkpointing safely rechecks/reuses identical items. Changed items fail closed, including source changes and runtime writes. A checkpoint race aborts rather than rewinding progress. Do not manually edit/delete the marker to force a resume.

## Historical mapping and duplicate policy

- Partition: `installment_id.to_i.to_s`. Recipient: SHA256 of `mailer_method + "\n" + mailer_args`. URL: SHA256 of the **raw stored encoded URL**. `mailer_args` must remain the original string: do not parse JSON, reserialize, trim, or normalize it. Do not decode `&#46;`, change a URL scheme, or strip a prefix before hashing. `view_attachments_url` remains a literal URL key.
- `OPEN#recipient`: union of stored timestamp sets, preserving repeat opens represented by `open_count` even when Mongo's `add_to_set` collapsed equal timestamps. First/last times come from the earliest/latest recorded timestamps, UTC ISO8601 with BSON's exact millisecond precision, never migration time or `updated_at`.
- Duplicate source `_id` reads are counted once; conflicting versions abort. Exact duplicate histories under different IDs count once. Disjoint open histories combine their counts. Overlapping histories without hidden repeats use a timestamp union. **Nonidentical overlapping histories with counts exceeding their timestamp-set size are ambiguous and abort**: there is no defensible way to infer whether hidden repeats are duplicated. Repair a separate frozen snapshot from authoritative logs and restart into a new empty target; do not choose a silent max/sum policy.
- `CLICK#recipient#url`: one unique pair, `click_count: 1`, earliest `first_click_at` and latest `last_click_at` across source duplicates. Upstream counts unique pairs, not repeated clicks.
- `CLICKER#recipient`: earliest/latest click across all URLs. `URL#url`: number of distinct recipient+URL pairs for that exact URL.
- A clicker with no open row gets one implied open at their earliest click; additional URLs do not create more opens. Existing open rows are preserved, not incremented for clicks (legacy Mongo already created implied opens).
- `SUMMARY.open_count` counts distinct open recipients; `click_count` counts distinct click recipients; `click_pair_count` counts recipient+URL pairs. CrowdChurn `total_unique_clicks` callers must use **click_count**, not click_pair_count.
- Legacy `creator_email_click_summaries` are deliberately not imported: their nontransactional increments can disagree with event documents. All derived items are rebuilt from event identity sets. Missing event documents cannot be reconstructed from summary counters; retain old summaries for audit and investigate discrepancies before cutover.
- Missing/malformed IDs, serialized arguments, timestamps or counts fail rather than fabricate historical data. Timestamp arrays are mandatory; timestamps finer than BSON milliseconds are rejected instead of truncated.

## Run and resume

Set credentials in the process environment using your secret manager, never checked-in files or command-line URI arguments:

- `EMAIL_ENGAGEMENT_MONGO_URI`: full Mongo/FerretDB URI, including authentication/TLS options when required.
- `EMAIL_ENGAGEMENT_MONGO_DATABASE`: restored snapshot database name.
- AWS SDK credentials/profile and `AWS_REGION` (or `--region`). Use `--endpoint` for self-hosted Dynamo-compatible services, not the app's MinIO endpoint.

Example (replace all identifiers with the approved deployment values):

```sh
bundle exec ruby script/email_engagement_migration import \
  --table migration-20260912-email_engagement \
  --active-table production-email_engagement \
  --run-id engagement-final-20260912 --snapshot-id frozen-final-20260912 \
  --source-frozen --target-isolated --region us-east-1
```

Re-run exactly that command after interruption. Successful import performs a full reconciliation and marks the target `reconciled`. Keep the JSON report (partitions, items, unique counts, repeat-open count, SHA256 of canonical items) as a deployment artifact. It contains no raw recipient arguments or URLs.

Run the same command with `reconcile` in place of `import` in a **separate invocation**, using fresh source/client connections. Reconciliation ignores checkpoints, rereads every source partition, compares all item attributes via strongly consistent paginated queries, and scans the entire target to detect foreign or extra partitions. Source/target must remain frozen: a Dynamo scan is not a cross-page transactional snapshot. The aggregate report is not based on the old Mongo summaries or imported counters alone.

Finally use `release` with the same options. Release repeats full reconciliation, requires the report to match the saved import report, and marks the target `released`. Import refuses released targets. There is no force/overwrite option.

## Catch-up and cutover

This is deliberately **not** an online dual-write or timestamp-watermark migration. Legacy open counts and timestamp arrays mutate existing documents; paging only new IDs or `updated_at` will lose updates. A rehearsal snapshot cannot be safely "caught up" by appending events to its target.

1. Rehearse import, independent reconciliation, and failure/resume against a restored snapshot and isolated disposable table. Investigate ambiguous rows and compare event-derived totals to legacy summary/cache values. Record duration/memory/capacity to plan the maintenance window.
2. Enter a maintenance window: pause provider callback consumption and engagement workers; durably buffer new callbacks. Drain all already accepted legacy engagement jobs and ensure their Mongo writes are complete. Pause any other Mongo engagement writers before taking the **final consistent snapshot** of both event collections. Do not migrate a changing live database.
3. Restore the final snapshot read-only. Import **the complete final snapshot into a new empty staging table with new run/snapshot IDs**, not into the rehearsal table. This full paused-write final pass is the catch-up strategy. If the window is too long, stop and design a separately reviewed CDC migration; this tool intentionally does not guess an online delta.
4. Run independent reconciliation and release while all engagement processing remains paused. Preserve reports and both source snapshots. If anything fails, resume against this same immutable snapshot or abandon the staged table; the live system has not been modified.
5. Set `EMAIL_ENGAGEMENT_DYNAMODB_TABLE_NAME` to the exact released table name on every process. This engagement-only override leaves other Dynamo stores and their `DYNAMODB_TABLE_PREFIX` untouched. Set `EMAIL_ENGAGEMENT_MIGRATION_RUN_ID` on **every web and worker process**; its initializer refuses boot unless that table's marker is released for the expected run. Update IAM access only now, deploy/restart all processes with the same target, and verify boot succeeds before reopening callbacks.
6. Invalidate/recompute Installment/PostVariant engagement caches using existing application operations, preserving CrowdChurn's distinct-recipient `total_unique_clicks` semantics. Do not replay already processed Mongo documents or old jobs as live events. Resume only callbacks buffered after the final legacy drain boundary; duplicates of open callbacks would increase repeat-open counts because the live upstream API has no provider-event-ID deduplication. Preserve the queue boundary as a cutover artifact.
7. Keep Mongo snapshots/backups read-only through the retention/acceptance period. Before new Dynamo writes, rollback can point back to the unchanged legacy system and replay only buffered callbacks. **After new Dynamo writes start, do not switch back to Mongo or rerun import**: that would lose post-cutover activity. Pause and plan a reverse reconciliation/replay from authoritative callback logs first.

Never use the CLI's `reconcile` as a repair job after runtime writes start: differences are then expected, and it intentionally performs no repair. The runtime boot marker is a release gate, not a distributed write lock; staging isolation is mandatory.

## Isolated validation

```sh
bundle exec rspec --options /dev/null spec/services/email_engagement_migration_spec.rb
```

These specs use a stateful stubbed Dynamo client and paginated source; they do not boot Rails, contact AWS/Mongo, send mail, or require local data services. Run existing `spec/services/email_engagement_dynamo_store_spec.rb` with the app's normal test setup when its services are available.
