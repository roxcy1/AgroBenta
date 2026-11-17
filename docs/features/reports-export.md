# Reports data export

Technical note for the Admin Web **Reports & Analytics** CSV download. It
describes the export the code implements; it is not a business-rule source.
Business rules stay in `docs/AGROBENTA_FUNCTIONAL_DOCUMENTATION.md`.

## Why it exists

The Reports screen summarises records — counts, trends, distributions and price
statistics. A summary file duplicates what the screen already shows, so the
export instead writes the **records behind one report section**: one CSV row per
stored record created inside the applied date range. Overview figures are not
exported.

## Endpoint

```
GET /api/admin/reports/export/{dataset}
    ?date_from=YYYY-MM-DD
    &date_to=YYYY-MM-DD
```

* Admin only: the route sits in the existing `auth:sanctum` + `admin` +
  `ability:admin` group.
* `dataset` is one of `transactions`, `listings`, `users`,
  `seller-verifications`, `activities`. Any other value is a `404`.
* `date_from` / `date_to` use the same validation as `GET /admin/reports`
  (`before_or_equal:today`, `date_to` on or after `date_from`), so an invalid
  range is a `422`.
* Response: `200 text/csv; charset=UTF-8` with
  `Content-Disposition: attachment; filename=agrobenta-reports-<dataset>-<range>-<timestamp>.csv`.

## Date rule

Every dataset filters on `created_at`, inclusive of the end date
(`<= date_to 23:59:59`), matching the report's date filter. A record is exported
in the period it was **created**, not when it was later completed, reviewed or
sold. With no range, every record is exported.

Rows are newest first (`created_at desc, id desc`).

## Columns

| Dataset | One row per | Columns |
|---|---|---|
| `transactions` | transaction | Transaction ID, Created At, Status, Fulfillment Status, Buyer ID/Name/Email, Seller ID/Name/Email, Listing ID, Livestock Type, Breed, Quantity, Total Amount, Pickup Date, Payment Method, Collection Method, Completed At |
| `listings` | listing | Listing ID, Created At, Status, Seller ID/Name/Email, Livestock Type, Breed, Gender, Age Value, Age Unit, Weight Value, Weight Unit, Quantity, Asking Price, Location, Health Status, Vaccination, Short Description |
| `users` | active account | User ID, Registered At, Name, Email, Role, Seller Capability, Email Verified At |
| `seller-verifications` | verification submission | Verification ID, Created At, Submitted At, Status, Seller ID, Applicant Name, Applicant Email, Business Name, Business Location, Government ID Type, Reviewed At, Reviewer Name, Admin Note |
| `activities` | activity | Activity ID, Created At, Actor ID, Actor Name, Actor Email, Action, Description |

Notes:

* Users exclude soft-deleted (deactivated) accounts, the same population the
  report totals count.
* Verifications are **not** deduplicated to the latest record per applicant; the
  report counts submissions, so the export keeps every submission.
* A deleted buyer, seller, reviewer or actor is still named (the relations read
  trashed accounts), matching the admin tables. A system activity has blank
  actor columns.

## CSV safety

* RFC 4180 quoting via PHP's `fputcsv` with an explicit empty escape character.
* Numeric cells stay numeric so spreadsheets can total them.
* Text beginning with `=`, `+`, `-`, `@`, tab or carriage return is prefixed
  with `'` to prevent spreadsheet formula execution.
* Rows stream through a lazy cursor; an all-time export is not loaded into
  memory.
* An empty result writes the header row only.
* No credentials, tokens or document storage paths are exported.

## Admin Web behaviour

`frontend/src/features/admin/reports/api/exportReport.ts` requests the CSV as a
blob; `buildReportExportFilename` names the browser download because the
cross-origin development API cannot expose `Content-Disposition` to the browser.
The dataset selector and CSV button sit in the report filter row, and the export
uses the currently **applied** date range (not dates typed but not applied).

## Validation

* `backend/tests/Feature/Admin/ReportExportTest.php` covers authorization,
  per-dataset headers and rows, range boundaries, empty ranges, unknown
  datasets, invalid ranges and formula neutralisation.
* `frontend/src/features/admin/reports/csv.test.ts` and
  `frontend/src/features/admin/reports/api/exportReport.test.ts` cover the
  filename and the request shape.
