---
name: review-sync-proc
description: Review an existing SQL Server sync, ETL, upsert or MERGE stored procedure for correctness bugs (missed changes, duplicates, lost watermarks, broken transactions) and propose fixes. Use when the user shares T-SQL that copies or syncs data and asks for a review, a bug hunt, or why rows are missing, duplicated or not updating.
---

# Review a SQL Server sync procedure

Read the whole procedure and any DDL the user shares. Then go through every item in `checklist.md` in this skill's folder. Report only real findings; don't pad with style comments.

## How to report

For each finding give:

1. **Severity**: Critical (data loss or wrong data), High (duplicates, missed changes under some conditions), Medium (performance, observability), Low.
2. **Where**: the statement or line.
3. **What goes wrong**: a concrete scenario, e.g. "a row whose `Phone` changes from NULL to a value is never updated".
4. **Fix**: the corrected T-SQL snippet.

Order findings by severity. End with a short list of tests that would have caught the Critical and High findings.

If the user asks for it, produce the full corrected procedure, changing only what the findings require, and list each change.
