# Accounts Receivable — Feature Parity Report
> Source of truth: codebase only (controllers, presenters, services, models, routes, views)
> Portal paths: `app/controllers/hotel_portal/` vs `app/controllers/corporate_portal/`

---

## 1. AR Invoices

| Feature | Hotel Portal | Corporate Portal | Notes |
|---|---|---|---|
| **Invoice list / index** | ✅ `ar_invoices#index` | ✅ `ar_invoices#index` | Both paginate; hotel uses presenter with rich filtering, corporate is a simple scoped query |
| **Invoice detail / show** | ✅ `ar_invoices#show` | ✅ `ar_invoices#show` | Both render allocation history; hotel shows payment method + technical snapshot metadata panel |
| **Filter by status** | ✅ (open, partially paid, paid, overdue, void) | ❌ Not implemented | Corporate only shows all invoices sorted by due date |
| **Filter by corporate account** | ✅ Dropdown filter | ❌ N/A (already scoped to own account) | Hotel needs cross-account selection |
| **Filter by due date** | ✅ Single date picker | ❌ Not implemented | Hotel only |
| **Filter by outstanding balance** | ✅ "Outstanding only" toggle | ❌ Not implemented | Hotel only |
| **Keyword / free-text search** | ✅ Searches invoice number, account name, booking ref, folio number, folio account ref | ❌ Not implemented | Hotel only |
| **Summary metrics dashboard** | ✅ Open AR, Overdue, Due Soon, Paid This Month (all multi-currency) | ❌ Not implemented | Corporate shows outstanding balance by currency in a simple aggregate — not the same |
| **Outstanding balance by currency** | ❌ Not on invoice index (on payments index instead) | ✅ `@outstanding_by_currency` on index | Different placement |
| **Overdue status auto-refresh** | ✅ `ArInvoices::RefreshOverdueStatuses` called before index & aging | ❌ Not triggered | Corporate portal never refreshes overdue statuses |
| **Invoice aging report** | ✅ `ar_invoices#aging` — full aging table with 5 buckets + credit exposure | ❌ Not implemented | Hotel only; requires `view_reports` permission |
| **Credit limit / exposure indicator** | ✅ On aging report per account | ❌ Not implemented | Hotel only |
| **Technical metadata snapshot** | ✅ Shown on invoice show (all metadata keys/values) | ❌ Not shown | Hotel only |
| **Payment terms display** | ✅ On invoice show | ❌ Not on corporate invoice show | Hotel only |
| **Direct bill source indicator** | ✅ Shows "Folio close" when applicable | ❌ Not shown | Hotel only |
| **Permission guard** | ✅ `view_reports` permission required | ❌ No extra guard — any corporate user can view | Different access control model |
| **Breadcrumb** | ❌ Not observed | ✅ `append_breadcrumb` in show | Corporate only |

---

## 2. AR Payments

| Feature | Hotel Portal | Corporate Portal | Notes |
|---|---|---|---|
| **Payment list / index** | ✅ `ar_payments#index` | ✅ `ar_payments#index` | Hotel shows hotel-scoped AR payments; corporate shows corporate intent-based payment history (mixed IntentRow + legacy PaymentRow) |
| **Payment detail / show** | ✅ `ar_payments#show` | ✅ `ar_payments#show` (shows `CorporateArPaymentIntent`, not `ArPayment` directly) | Corporate shows the payment intent; hotel shows the actual `ArPayment` record |
| **Record new payment (manual)** | ✅ `ar_payments#new` + `#create` — hotel staff enters amount, reference, method, date, notes, optional allocations | ❌ Not available | Corporate uses online gateway flow instead |
| **Online payment (gateway)** | ❌ Not available | ✅ `pay_invoices` → `review` → `checkout_session` → `verify` (Razorpay only) | Corporate only; hotel staff record payments offline |
| **Invoice selection before payment** | ✅ `eligible_invoices` AJAX endpoint — hotel picks invoices when recording | ✅ Corporate selects invoices on `pay_invoices` page | Both select invoices; hotel allows partial amounts, corporate calculates default as full outstanding |
| **Payment allocation at creation time** | ✅ Optional — allocations submitted alongside payment creation | ✅ Remittance suggestions stored in intent snapshots (hotel later allocates) | Corporate suggests allocations but hotel finance actually allocates them |
| **Allocate unapplied balance post-creation** | ✅ `ar_payment_allocations#create` on hotel payment show page | ❌ Not available in corporate portal | Hotel only (hotel staff allocates) |
| **Reverse an allocation** | ✅ `ar_payment_allocation_reversals#create` with mandatory reason | ❌ Not available in corporate portal | Hotel only (hotel staff reverses) |
| **Filter by allocation status** | ✅ Unapplied / Partially allocated / Fully allocated | ❌ No filtering on payment history | Hotel only |
| **Filter by corporate account** | ✅ Dropdown filter | ❌ N/A (scoped to own account) | Hotel only |
| **Filter by date range** | ✅ Received-from / Received-to | ❌ Not implemented | Hotel only |
| **Filter by keyword** | ✅ Reference number, account name | ❌ Not implemented | Hotel only |
| **Summary metrics dashboard** | ✅ Received This Month, Allocated This Month, Total Unapplied, Needs Allocation count | ❌ Not implemented | Hotel only |
| **Payment method display** | ✅ (bank transfer, cheque, cash, card, other) | ✅ Shows gateway method from intent (`card` or `other`) | Hotel supports more manual methods |
| **Notes field** | ✅ Displayed on show page | ❌ Not shown | Hotel only |
| **Gateway / remittance metadata** | ✅ Shown on hotel payment show (gateway reference, gateway name, remittance suggestions) | ✅ Intent show also shows external reference | Both show gateway info but from different records |
| **Allocation history on show** | ✅ Full allocation table with reversal details (reason, reversed by, reversed at) | ❌ Not shown on corporate payment show | Hotel only |
| **Permission guard** | ✅ `view_reports` to view, `manage_ar_payments` to create/allocate/reverse | ❌ No specific AR permission — any corporate user with account access | Different access control model |
| **Supported payment gateways** | ❌ N/A (manual only) | ✅ Razorpay only (hardcoded validation in `CreateIntent` and `InitializeCheckout`) | Corporate-only; gateway extensible but currently locked to Razorpay |
| **Payment intent expiry** | ❌ N/A | ✅ Intent expires after 30 minutes (`expires_at: 30.minutes.from_now`) | Corporate only |
| **Webhook processing** | ❌ N/A | ✅ `CorporateArPayments::ProcessWebhook` service exists | Corporate only |

---

## 3. AR Statements

| Feature | Hotel Portal | Corporate Portal | Notes |
|---|---|---|---|
| **Statement index (all accounts)** | ✅ `ar_statements#index` — lists all hotel corporate accounts with last activity, balance, unapplied credit | ❌ Not implemented | Hotel only |
| **Statement detail (single account)** | ✅ `ar_statements#show` — period ledger, opening/closing balance, invoices, payments, aging, unapplied credit | ❌ Not implemented | Hotel only |
| **Statement date range filter** | ✅ Start date / end date (defaults to start of business month) | ❌ N/A | Hotel only |
| **Statement currency filter** | ✅ Multi-currency selection | ❌ N/A | Hotel only |
| **PDF export of statement** | ✅ `format.pdf` responds with generated PDF via `Reports::AccountsReceivable::GenerateStatement` | ❌ N/A | Hotel only |
| **Statement search by account / user email** | ✅ Search on statements index | ❌ N/A | Hotel only |
| **Payment terms display** | ✅ Shown on statement | ❌ N/A | Hotel only |
| **Aging summary on statement** | ✅ Included in statement report | ❌ N/A | Hotel only |
| **Permission guard** | ✅ `view_reports` | ❌ N/A | Hotel only |

---

## 4. Access Control & Permissions

| Aspect | Hotel Portal | Corporate Portal |
|---|---|---|
| **Who can view invoices / payments** | Users with `view_reports` permission on the hotel | Any authenticated corporate user |
| **Who can record payments** | Users with `manage_ar_payments` permission | N/A (online gateway only — no manual recording) |
| **Who can allocate payments** | Users with `manage_ar_payments` permission | N/A (hotel finance allocates after gateway capture) |
| **Who can reverse allocations** | Users with `manage_ar_payments` permission | N/A |
| **Data scope** | Scoped to `current_hotel` | Scoped to `current_user.account` (corporate account across all hotels) |
| **Multi-hotel view** | No — one hotel at a time | Yes — corporate sees invoices/payments across all linked hotels |

---

## 5. Shared Domain Model (Both Portals)

| Model | Used by Hotel Portal | Used by Corporate Portal |
|---|---|---|
| `ArInvoice` | ✅ Read + status refresh | ✅ Read only |
| `ArPayment` | ✅ Read + create (via service) | ✅ Read (created by gateway capture) |
| `ArPaymentAllocation` | ✅ Create + reverse | ❌ Not directly managed |
| `ArPaymentAllocationReversal` | ✅ Create | ❌ Not accessible |
| `CorporateArPaymentIntent` | ❌ Not used | ✅ Create + track lifecycle |
| `HotelCorporateAccount` | ✅ Full CRUD (suspend/reactivate) | ✅ Read only (active only) |

---

## 6. Summary — Feature Gap Table

| Feature Area | Hotel Portal | Corporate Portal | Gap |
|---|---|---|---|
| Invoice list | ✅ Rich (filter, search, metrics) | ✅ Basic (no filter) | **Corporate missing**: filters, search, metrics, overdue refresh |
| Invoice detail | ✅ Full (metadata, terms, source) | ✅ Partial | **Corporate missing**: metadata, terms, direct bill source |
| Invoice aging report | ✅ Full | ❌ None | **Corporate missing**: entire aging feature |
| AR statements | ✅ Full (PDF, ledger, aging) | ❌ None | **Corporate missing**: entire statements feature |
| Payment list | ✅ Rich (filter, search, metrics) | ✅ Basic (history only, no filter) | **Corporate missing**: filters, search, metrics |
| Payment detail | ✅ Full (allocation history, reversal) | ✅ Partial (intent-based) | **Corporate missing**: allocation history, reversal view |
| Record payment (manual) | ✅ Full | ❌ None | **Hotel missing**: online gateway |
| Online payment (gateway) | ❌ None | ✅ Full (Razorpay) | **Hotel missing**: online payment flow |
| Post-creation allocation | ✅ Full | ❌ None | **Corporate missing**: allocation management |
| Allocation reversal | ✅ Full | ❌ None | **Corporate missing**: reversal capability |
| Credit exposure tracking | ✅ On aging report | ❌ None | **Corporate missing**: credit limit visibility |
| Multi-hotel AR view | ❌ Per hotel only | ✅ Cross-hotel | **Hotel missing**: cross-hotel aggregation |
| PDF export | ✅ Statements | ❌ None | **Corporate missing**: any export |
| Permission granularity | ✅ Role-based (`view_reports`, `manage_ar_payments`) | ❌ Account-level only | **Corporate missing**: granular AR permissions |
