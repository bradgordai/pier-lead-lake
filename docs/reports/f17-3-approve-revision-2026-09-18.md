# F17.3 Approve shows success and error together (i096) — 2026-09-18

## Which cause: the revision number, NOT a double fire
I did not run the test by clicking Approve (the brief forbids me Approve). Production had already run it:
every approval 15-18 Sep, grouped by how many revisions the draft had BEFORE it was approved.

| Revisions before approval | Drafts approved | Revision written at approval |
|---|---|---|
| 0 (never revised) | 8 | 8 of 8 succeeded |
| 1 | 9 | 3 (each written by a Save seconds earlier, not by Approve). **6 failed = the six reported cards** |
| 2 | 3 | 1 |
| 3, 4 | 2 | 0 |

A never-revised draft approves cleanly every time, so the approval is not firing twice. Approve inserts a
revision whose number the app computes from a count; numbering starts at 0, so with revision 0 present the
count lands on a taken number. Every draft shows exactly one approve transition in audit_log.
The two green toasts on one card are a separate, cosmetic UI double-render; not reproduced in data.

## (e) Nothing was lost — confirmed independently
All 22 approvals since 15 Sep have their draft_status transition in audit_log and read `approved` now. Only
the revision snapshot failed. No approval needs redoing.

## Fixed now, server side (migration 110, applied, tested in a rolled-back transaction)
(b) `revision_number` is assigned in the database: a BEFORE INSERT trigger turns a missing or taken number
into max+1 for that draft, serialised per draft. Test: sent 0 twice to a draft that already had 0; stored as
2 and 3, no error. The unique constraint stays as the guard. **The red toast is gone without any Lovable
change**, and a repeated write can no longer fail, which is the write half of (a).

## For Lovable (UI half of (a), and (d)) — paste
> Do not pause for a plan. In the Approve action: (1) disable the Approve button from click until the
> request settles; (2) stop computing `revision_number` in the client or server function: omit the field
> from the `draft_revisions` insert, the database assigns it; (3) do not insert a revision on Approve at all
> unless the message text differs from the latest revision's text; (4) show exactly one toast per action:
> success only if every write succeeded, otherwise one error toast and no success toast. Apply (4) to
> Reject, Save and Send now as well.

## (c) Should approving write a revision at all? No.
A revision records a change of TEXT. Approve changes STATUS, and that is already recorded with actor and
time in audit_log. When the text is unchanged, approving is a status change on the revision that exists.
The only case for a write is approve-with-unsaved-edits, which is a Save followed by an Approve.
Zero rows have ever carried an approve source: every "approval" revision is labelled `original`, i.e. the
app was lazily back-filling revision 0 at approval time. That back-fill belongs at draft creation.

## i-number status
- i096: cause proven (revision number computed in app code), server fix live, approvals intact. UI polish
  (button disable, single toast) is the Lovable prompt above.
