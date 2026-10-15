---
name: generate-merge-sync
description: Generate a production-ready T-SQL stored procedure that incrementally syncs one table to another with a watermark or Change Tracking, MERGE upsert, transaction, TRY/CATCH and error logging. Use when the user asks to write, create or convert a sync, upsert or MERGE procedure for SQL Server.
---

# Generate an incremental MERGE sync procedure

Write the procedure from the user's actual table definitions. If you do not have the DDL for source and target, ask for it (or the column list and keys) before writing code. Never invent column names.

Start from `template.sql` in this skill's folder and adapt it. Keep its structure unless the user asks otherwise.

## Rules the generated code must follow

1. `SET NOCOUNT ON; SET XACT_ABORT ON;` at the top.
2. Read the watermark into a variable, and capture the upper bound (`MIN_ACTIVE_ROWVERSION()`, `SYSUTCDATETIME()`, or `CHANGE_TRACKING_CURRENT_VERSION()`) **before** reading changes, so rows written during the run are picked up next time, not lost.
3. Stage the changed source rows into a temp table first, with the match key as its primary key. If the source can return duplicates per key, deduplicate with `ROW_NUMBER()` and keep the latest. A `MERGE` with duplicate source keys fails.
4. `MERGE` with `WITH (HOLDLOCK)` on the target. Match on the business key.
5. In `WHEN MATCHED`, update only when something changed, using a NULL-safe comparison:
   `AND EXISTS (SELECT s.Col1, s.Col2 EXCEPT SELECT t.Col1, t.Col2)`.
   Never compare nullable columns with `<>` alone; `NULL <> 'x'` is not true, so the change is missed.
6. Capture counts with `OUTPUT $action INTO @Actions`.
7. Update the watermark inside the same transaction as the data, after the `MERGE`.
8. In `CATCH`: `IF XACT_STATE() <> 0 ROLLBACK;`, write to the error log table, then `THROW;` so the Agent job fails visibly.
9. Name every column explicitly; never `SELECT *` or `INSERT` without a column list.
10. For Change Tracking: check `CHANGE_TRACKING_MIN_VALID_VERSION` first and raise a clear error asking for a full reload when the stored version is too old.

## After generating

- List any assumptions (key choice, delete handling, column mappings).
- Give a short test script: run once, change a row with a NULL to non-NULL value, run again, run a third time with no changes and confirm 0 updates.
- Offer a review with `/sqlserver-sync-toolkit:review-sync-proc`.
