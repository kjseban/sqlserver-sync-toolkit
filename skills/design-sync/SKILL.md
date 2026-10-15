---
name: design-sync
description: Design an incremental data-sync strategy between SQL Server databases or tables. Use when the user wants to copy, replicate or keep tables in step between databases, asks how to detect changed rows, or must choose between rowversion/timestamp watermarks, ModifiedDate watermarks, Change Tracking, CDC or full compare.
---

# Design an incremental SQL Server sync

Help the user pick and document a sync design before any code is written. Ask only for what you cannot find in the schema or code they share.

## 1. Gather the facts

Find out, from the DDL or by asking:

- Source and target: same instance, linked server, or separate servers? Same edition and version?
- For each table: primary key, natural/business key, approximate row count, daily change volume.
- Are deletes possible in the source, and must they reach the target?
- Is there a reliable change marker: a `rowversion` column, a `ModifiedDate` that every writer updates, or neither?
- Can the source schema or database settings be changed (enable Change Tracking, add a column)?
- Required latency (minutes, hourly, nightly) and the scheduler (SQL Server Agent, app service, SSIS).
- Parent/child dependencies between the tables (load order).

## 2. Choose the change-detection method

| Method | Use when | Watch out for |
|---|---|---|
| `rowversion` watermark | You can add a column; inserts and updates only | Does not see deletes; compare with `MIN_ACTIVE_ROWVERSION()` to avoid skipping in-flight transactions |
| `ModifiedDate` watermark | Column already exists and every writer sets it | Clock skew, writers that forget to set it, equal timestamps at the boundary; use `>=` with a small overlap and make the load idempotent |
| Change Tracking | You can enable it on the source DB; deletes matter | Retention period: if the last synced version is below `CHANGE_TRACKING_MIN_VALID_VERSION`, a full reload is required |
| CDC | You need the old and new values or full history | Heavier; needs SQL Agent on source |
| Full compare (`EXCEPT` / hash) | Small tables, or no change marker at all | Cost grows with table size |

Recommend one method per table and say why in one line each.

## 3. Design the moving parts

Cover each of these in the design:

- **Watermark store**: one control table, e.g. `dbo.SyncWatermark (SyncName, TableName, LastValue, LastRunUtc, RowsAffected)`. The watermark advances only after the data commits, in the same transaction.
- **Key mapping**: if the target has its own identity keys, a mapping on the business key. Never key the match on a value the source can change (e.g. a hash of an editable column such as an ID number); that creates duplicates when the value changes.
- **Upsert**: `MERGE` or separate `UPDATE`/`INSERT` (see the `generate-merge-sync` skill).
- **Deletes**: hard delete, soft delete flag, or ignore. State which.
- **Load order**: parents before children for inserts, children before parents for deletes.
- **Error handling**: `TRY/CATCH`, `XACT_ABORT ON`, an error log table, and rethrow so the Agent job shows failure.
- **Restartability**: re-running after a failure must not duplicate rows or skip changes.
- **Monitoring**: rows affected per run, duration, and an alert when the watermark stops moving.

## 4. Output

Give the user a short design note with: the method per table, the control and log table DDL, the run sequence, the failure/restart behaviour, and open questions. Offer to generate the procedure next with `/sqlserver-sync-toolkit:generate-merge-sync`.
