# Documents and Invoicing Plan

## Confirmed Rules

| Folio outcome | Official document |
|---|---|
| Guest pays and balance becomes zero | Folio invoice |
| Corporate account pays immediately by cash, card, or bank | Folio invoice addressed to the company |
| Corporate account uses Direct Bill | AR invoice only |
| Folio remains open under an approved exception | No invoice |
| Folio is voided | No new invoice |

A Direct Bill folio must never receive both a folio invoice and an AR invoice.

Each folio keeps its own official invoice. When several invoices are emailed together, they are delivered as one consolidated package rather than replaced by another official invoice.

## 1. Invoice Records and History

Add a proper record for each folio invoice instead of relying only on invoice-number fields on `BookingFolio`.

A folio invoice will hold:

- The base number allocated by the Document Identifier Registry.
- Current state: `finalized`, `under_correction`, or `voided`.
- Current revision number.
- Issue date and issuing staff member.
- The associated folio and hotel.
- Immutable revisions containing the document's historical contents.

Each revision will snapshot:

- Hotel details.
- Guest or corporate payer details.
- Booking and room details.
- Folio transactions.
- Taxes and transaction codes.
- Payment references.
- Currency and totals.
- Purchase order and authorization references.
- Printed invoice identifier.

Existing folio invoice fields will be backfilled into the new records. Historical identifiers will not be deleted or renumbered.

## 2. Document Identifiers and Revisions

The first invoice number will come from the existing Document Identifier Registry.

Example:

```text
INV-2026-000123
```

If the folio is reopened and corrected:

```text
INV-2026-000123-2
INV-2026-000123-3
```

Rules:

- The base number comes from the registry only once.
- Revision suffixes do not consume registry numbers.
- The original invoice has no `-1` suffix.
- Payments continue referencing the base invoice number.
- PDFs and document history show the complete revision identifier.
- Previous revisions remain available to authorized staff for audit purposes.

## 3. Reopening Folios

When an invoiced folio is reopened:

1. The invoice enters `under_correction`.
2. The current invoice cannot be sent as the active invoice.
3. The previous finalized revision remains unchanged in audit history.
4. The reopen reason, staff member, and time are recorded.
5. When the folio closes again, revision `-2`, `-3`, and so on is created.
6. The newest revision becomes the current invoice.

Reopening does not allocate another base invoice number.

Direct Bill folios with an active AR invoice will not use this folio revision process. They require the AR invoice to be voided or corrected through the AR workflow before financial changes are allowed.

## 4. Shared Folio Closure Rules

Create one shared service that decides what document should be issued when a folio closes.

Both checkout and manual folio-window closure will use it.

The decision happens separately for every folio:

- Closed with zero balance: issue or finalize a folio invoice.
- Closed using Direct Bill: create an AR invoice only.
- Reclosed after correction: create the next folio invoice revision.
- Left open: issue nothing.
- Voided: issue nothing.

Identifier allocation will happen inside the same database transaction as folio closure.

This replaces the current behavior that allocates one invoice number before determining the primary folio's settlement method.

## 5. Folio Invoice Generator

Refactor the existing invoice generator to operate on a specific folio and its finalized invoice revision.

```ruby
Reports::Bookings::GenerateInvoice.new(
  folio: booking_folio,
  printed_by: current_user.name
).generate
```

It will:

- Use only that folio's transactions.
- Use the folio's currency.
- Use the folio's invoice identifier.
- Show the folio's room when it is room-specific.
- Render from the finalized snapshot.
- Reject open or under-correction invoices.
- Reject Direct Bill folios that have an AR invoice.

Authorized audit screens may request a specific historical revision.

## 6. Folio Ledger Generator

Make the ledger explicitly folio-specific:

```ruby
Reports::Bookings::GenerateFolioLedger.new(
  folio: booking_folio,
  printed_by: current_user.name
)
```

The ledger:

- Is not an invoice.
- Does not allocate an invoice number.
- Can be generated for open, closed, or voided folios.
- Shows the folio's complete transaction history.
- Clearly displays the folio's status.

## 7. Corporate Payers

Corporate payer behavior depends on settlement method.

### Immediate Payment

When a corporate account pays by cash, card, or bank and the folio reaches zero:

- Generate a normal folio invoice.
- Address it to the corporate payer.
- Include company name, account type, PO reference, and authorization reference.
- Include it in a corporate invoice email package where applicable.

### Direct Bill

When payment is deferred to the corporate account:

- Do not create a folio invoice.
- Create one AR invoice.
- Preserve the outstanding receivable until AR payments settle it.

Paying an AR invoice later does not convert it into a folio invoice.

## 8. AR Invoice PDF

Add a dedicated generator:

```ruby
Reports::AccountsReceivable::GenerateInvoice.new(
  invoice: ar_invoice,
  printed_by: current_user.name
).generate
```

The PDF will show:

- AR invoice number.
- Corporate payer and account type.
- Booking, room, and folio reference.
- Issue and due dates.
- Purchase order and authorization references.
- Original folio charge lines.
- Original invoice amount.
- Paid amount.
- Outstanding amount.
- Payment terms.
- Current status.

Issue-time payer details and charge lines will be snapshotted. Paid and outstanding amounts may reflect current AR payment activity.

Paid and void AR invoices remain viewable with the appropriate status clearly displayed.

## 9. Existing Public Links

Preserve current public, guest-portal, and legacy email links through an explicit adapter:

```ruby
Reports::Bookings::GeneratePrimaryGuestInvoice
```

The adapter will:

- Resolve the guest-facing primary folio deliberately.
- Exclude corporate and Direct Bill documents.
- Return only a finalized invoice.
- Use the folio-specific generator.

New hotel workspace routes will always use `folio_id`, folio invoice ID, revision ID, or `ar_invoice_id`.

## 10. Consolidated Email Packages

Multi-folio invoices are sent as one email with one combined PDF package. The combined PDF is drawn directly with the existing Prawn dependency; it is not assembled from files and is never delivered as a ZIP.

The package contains both:

1. A summary page listing all included folios, invoice numbers, currencies, and totals.
2. Every complete folio invoice on the following pages.

Important rules:

- Each folio invoice retains its own official number.
- The summary does not receive an invoice number.
- The package does not create another invoice or receivable.
- Different currencies are shown in separate total sections and are never added together.
- Under-correction or voided invoices are excluded from normal sending.
- The email job receives explicit invoice IDs rather than only a booking ID.
- Each complete invoice is drawn into the package's existing `Prawn::Document` and starts on a new page.
- One package-wide footer and page sequence is applied after all invoice pages are drawn.
- No temporary PDFs, PDF concatenation library, or new gem is required.

Packages will be separated by payer to prevent financial information from being sent to the wrong recipient:

- Guest-paid folios go to the relevant guest.
- Corporate-paid folios go to the corporate payer contact.
- Direct Bill AR invoices follow the corporate AR delivery workflow.
- Different payers never share one package.

Checkout queues these payer-separated packages automatically. The delivery coordinator resolves saved recipients, revalidates the explicit current revision IDs immediately before delivery, records every attempt in `NotificationDelivery`, and uses a stable idempotency key for automatic checkout attempts. The former booking-ID email job remains only as a compatibility wrapper for jobs already in the queue.

## 11. Documents Query and Catalog

Add:

```ruby
HotelPortal::Bookings::DocumentsQuery.call(
  booking: booking,
  group_booking: booking.group_booking
)
```

It will build document rows from all relevant child bookings and load:

- Rooms and guests.
- Every booking folio.
- Folio invoice revisions.
- Billing parties and corporate accounts.
- AR invoices.
- Folio transactions and transaction codes.
- Payment receipts.
- Booking and group deposit receipts.
- Guest registration cards.

Balances will be calculated using grouped queries instead of repeatedly calling model methods that perform separate sums.

The existing universal workspace loading will be made tab-aware so this expensive document data is only fetched for `tab=documents`.

## 12. Documents Tab

Add Documents as a standard booking workspace tab.

The canonical URL is:

```ruby
hotel_booking_workspace_path(hotel, booking, tab: "documents")
```

Documents will not use entity mode, a desktop left rail, a mobile entity sheet, room selection, or document-specific URL state. A legacy `child_booking_id` parameter on this tab will be ignored and will not filter the catalog.

For standalone bookings it will show documents for every folio.

For group bookings it will show documents across every child booking and room.

Document types include:

- Folio invoices.
- Historical invoice revisions.
- AR invoices.
- Folio ledgers.
- Payment receipts.
- Deposit receipts.
- Group deposit receipts.
- Guest registration cards.
- Payer statements.

The complete catalog will be presented as four vertically stacked, full-width table sections:

1. Invoices.
2. Folio ledgers.
3. Receipts.
4. Utility.

The sections use context-specific columns:

- Invoices: invoice number, folio type, booking and room, payer, issue date, amount, and action.
- Folio ledgers: folio number, folio type, booking and room, payer, issue date, balance, and action.
- Receipts: receipt number, receipt type, booking and room, payer, issue date, amount, and action.
- Utility: document number, document type, booking and room, subject, issue date, and action.

Invoice and ledger folio types use the underlying folio category: Guest, External, or House. Receipt and Utility type columns retain their document-specific classification.

Status is displayed in the first column with the document number. An unavailable reason appears on the same secondary line as the status. Text-heavy cells are limited to two visible lines to keep row height controlled. The tables do not use hover popovers.

When all monetary rows in a section use one currency, the currency moves into the column heading, such as `Amount (MYR)` or `Balance (MYR)`. Mixed-currency sections retain the currency on each row. Monetary values do not wrap.

Column widths are normalized by role. On narrow screens, each table scrolls inside its own responsive wrapper while the Documents panel remains within the workspace viewport.

Unavailable documents will display a reason, such as:

- Folio still open.
- Invoice under correction.
- Direct Bill uses AR invoice.
- No receipt has been issued.
- Permission required.

The catalog will not add filters, selectors, search, pagination, new routes, or new query parameters at this stage.

## 13. Permissions

Document access will be checked by document type.

Examples:

- Booking and folio documents require booking-view permission.
- Registration cards retain their existing restricted permission.
- AR invoices and payer statements require report or AR permission.
- Historical invoice revisions require financial audit access.
- Sending documents requires the relevant management permission.

Opening the Documents tab will not automatically grant access to every document listed there.

All hotel routes will load records through `current_hotel` to enforce tenant separation.

## 14. Quick Documents and Resend

The booking Actions menu opens a compact PanelsUI Quick Documents side sheet.

For a standalone booking it offers one **Open** shortcut for Invoice, Receipt, Registration Card, and Tourism Tax Voucher when applicable. For a group it shows compact document counts only; it does not show room selectors, child-booking rows, or long document tables. Both variants link to the complete Documents tab.

Invoice delivery uses one compact **Resend** action in both the sheet and the Invoices heading on the complete Documents tab. Staff do not select invoice rows or edit recipients. The server discovers all current eligible finalized invoices and separates them by payer automatically.

The Resend tooltip states where delivery will go, how many saved payer contacts will receive separate emails, or why the action is unavailable. Confirmation lists payer name, saved email, and invoice count. Payers without a saved email are visible as skipped. Confirming once queues every valid payer package. Resend requires `manage_bookings`; opening individual documents keeps its document-specific permission.

## 15. Consolidated Payer Statements

Reuse and extend the existing AR statement system:

```ruby
Reports::AccountsReceivable::GenerateGroupStatement.new(
  group_booking: group,
  hotel: hotel,
  ar_invoice_ids: selected_invoice_ids
).generate
```

Validation will ensure:

- Every invoice belongs to the current hotel.
- Every invoice belongs to the supplied group booking.
- Every invoice belongs to the same hotel corporate account.
- Every invoice uses the same currency.
- Duplicate IDs are rejected.
- Unauthorized invoices cannot be inferred or accessed.

The output will:

- Be clearly marked **Statement**.
- Preserve every original AR invoice number.
- Show payments and outstanding amounts.
- Not create a database receivable.
- Not allocate a document identifier.

This explicit selection exists only for the accounting-specific **Generate group statement** action on the full Documents tab. It returns an inline PDF and does not send email.

## 16. Historical Records

Existing data will be handled conservatively.

- Existing folio invoice numbers are preserved.
- Existing AR invoice numbers are preserved.
- Existing Direct Bill folios that already have both identifiers are not rewritten.
- The AR invoice is treated as the payable document for those legacy cases.
- The old folio document is marked as a legacy document where necessary.
- Missing historical snapshots will render from available records and be marked as legacy-generated.
- New rules apply prospectively after deployment.

## 17. Delivery Order

1. Add folio invoice and revision records, states, and snapshots.
2. Backfill existing invoice identifiers without renumbering.
3. Add the shared folio closure and document issuance policy.
4. Correct checkout and manual folio closure.
5. Refactor invoice and ledger generators to be folio-specific.
6. Add reopen, correction, and revision-suffix behavior.
7. Snapshot AR billing data and add the AR invoice PDF.
8. Replace booking-based email jobs with payer-specific document packages.
9. Add compatibility adapters for existing public links.
10. Refactor workspace loading to support tab-specific queries.
11. Add the document catalog and availability rules.
12. Build the standard Documents tab with stacked catalog tables.
13. Restore Print / Send as the compact Quick Documents sheet and add one-click payer-aware Resend.
14. Extend the existing statement system for selected group invoices.
15. Add automatic checkout delivery, payer-separated Prawn packages, and delivery audit logging.
16. Complete accounting, permission, migration, and query-count tests.

## 18. Required Testing

The test suite will cover:

- Multiple settled folios receiving separate identifiers.
- One consolidated email containing summary and full invoices.
- Corporate accounts paying immediately.
- Direct Bill producing only an AR invoice.
- Primary and secondary Direct Bill folios.
- Manual folio closure and booking checkout.
- Reopen and revision suffixes.
- Concurrent invoice allocation.
- Historical invoice revisions remaining unchanged.
- Group bookings with multiple rooms and payers.
- Mixed-currency packages and statements.
- Guest, corporate, and AR email recipients.
- Prevention of cross-payer information exposure.
- Legacy Direct Bill records with duplicate document types.
- Public-link compatibility.
- Hotel tenant isolation.
- Document-level permissions.
- Documents-tab query counts for large groups.
- Standard Documents layout without an entity rail or mobile selector.
- Complete grouped catalogs when `child_booking_id` is absent, valid, foreign, or stale.
- Booking and room context on every document row.
- Context-specific folio, receipt, and utility type columns.
- Currency-in-heading behavior for single-currency sections and row-level currency for mixed sections.
- Two-line cell limits and table-wrapper-only horizontal overflow on narrow screens.
