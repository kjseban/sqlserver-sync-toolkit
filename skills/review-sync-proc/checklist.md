# Sync procedure review checklist

## Change detection and watermark
- [ ] Upper bound captured **before** reading changes (not `MAX(RowVer)` of what was read after the fact).
- [ ] `rowversion` upper bound uses `MIN_ACTIVE_ROWVERSION()` so in-flight transactions aren't skipped.
- [ ] Date watermarks: boundary handled (`>=` with overlap, or `>` with a tie-breaker); load is idempotent.
- [ ] Watermark is updated inside the same transaction as the data, after it succeeds.
- [ ] Watermark is not advanced when the run fails or reads zero rows because of an error.
- [ ] Watermark row exists on first run (seeded or inserted).
- [ ] Change Tracking: last version checked against `CHANGE_TRACKING_MIN_VALID_VERSION`.

## MERGE / upsert correctness
- [ ] Source is unique on the match key (dedupe with `ROW_NUMBER()`); otherwise MERGE error 8672 or nondeterministic updates.
- [ ] Match key is stable; not derived from a column the source can change (hash of an editable value causes duplicates).
- [ ] Change test is NULL-safe (`EXISTS (SELECT s.* EXCEPT SELECT t.*)` pattern), not `s.Col <> t.Col`.
- [ ] Every target column that should sync is in both the UPDATE and the INSERT lists; no missing columns.
- [ ] Column lists are explicit; no `SELECT *` / positional INSERT.
- [ ] `WHEN NOT MATCHED BY SOURCE THEN DELETE` is used only against a full source set, never against an incremental change set.
- [ ] `WITH (HOLDLOCK)` on the MERGE target when concurrent writers are possible.
- [ ] Data types and lengths match (silent truncation, implicit conversions in the join).

## Transactions and errors
- [ ] `SET XACT_ABORT ON`.
- [ ] `BEGIN TRAN` / `COMMIT` balanced on every path; no early `RETURN` leaving a transaction open.
- [ ] CATCH checks `XACT_STATE()` before rollback.
- [ ] Error logged after the rollback (otherwise the log row is rolled back too).
- [ ] Error rethrown (`THROW`) so the caller or Agent job sees failure.
- [ ] `@@TRANCOUNT` handled correctly if the proc can be called inside an outer transaction.

## Ordering and integrity
- [ ] Parent tables loaded before children; deletes in reverse order.
- [ ] Foreign-key or identity mapping between source and target keys is correct.
- [ ] Deletes in the source are handled as designed (hard, soft, ignored) and documented.

## Performance and operations
- [ ] Index on the source change column and on the target match key.
- [ ] Large batches split, or staging table used, to limit lock time and log growth.
- [ ] Rows inserted/updated/deleted recorded per run.
- [ ] Safe to re-run after failure (no duplicates, no skipped rows).
