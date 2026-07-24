# Folio service verbs

> Status: **Active convention.** Written as PR 1 of
> `docs/folios-services-reorg-proposal.md`.
> Scope: `app/services/folios/` and `app/services/folio_routing/`.

Forty-one services share a handful of verbs, and until now none of them was
written down — so `generate`, `sync` and `refresh` drifted into meaning roughly
the same thing, and one of them turned out to be a literal alias for another.
This page fixes the meanings. Read it before naming a new folio service.

The rule of thumb: **the verb tells you what the service does to the ledger.**
Whether it writes, whether it is safe to call twice, and whether the money moved
here or somewhere else.

## Writing money onto a folio

| Verb | Means | Examples |
|---|---|---|
| `post` | Creates a guest-visible charge or credit on a folio, through the posting guards. The domain-level verb — this is what staff would call it. | `PostNightlyCharges`, `PostCategoryCharge`, `PostEarlyCheckoutCharges`, `PostStaffTransaction` |
| `insert` | The low-level primitive that writes one `FolioTransaction` row. Thirteen services call `InsertTransaction`; it is the floor everything else builds on. **Do not name a domain operation `insert`** — if staff would recognise it, it is a `post` or a `record`. | `InsertTransaction` |
| `record` | The money already moved **somewhere else** — a gateway capture, an approved refund, cash taken at the desk. We are writing down a fact, not creating a charge. | `RecordPaymentFromGateway`, `RecordRefund`, `RecordTourismTaxPayment` |

## Keeping a folio in step with something else

| Verb | Means | Examples |
|---|---|---|
| `sync` | Makes one folio's state match a source of truth, **idempotently**. Creates what is missing, supersedes what no longer applies, leaves alone what is already right. Safe to call repeatedly — that is the defining property. | `SyncForecastedCharges`, `SyncExistingPayments` |
| `refresh` | A `sync` swept across a scope you did not hand it — every open folio in a hotel — usually because a rule changed underneath them. **One folio is a sync; a sweep is a refresh.** | `RefreshOpenForecastsFromRoomRevenueRules`, `FolioRouting::RefreshBookingForecasts` |
| ~~`generate`~~ | **Retired.** `GenerateForecastedCharges` was fifteen lines that called `SyncForecastedCharges` and nothing else, so the distinction never existed in the code. Do not reintroduce it: anything that builds records from a source, idempotently, is a `sync`. | — |

## Reading without writing

These must not touch the database. If one starts writing, it has become a `sync`
or an `apply` and should be renamed.

| Verb | Means | Examples |
|---|---|---|
| `calculate` | Pure computation from its arguments. | `NightlyChargeCalculation` (mixin) |
| `reconcile` | Compares expected against actual and **reports the differences**. Answers "is this right?", never "make it right". | `NightlyChargeReconciliation` |
| `resolve` | Answers "which one?" and returns it. | `ResolveTargetFolio` |
| `preview` | A dry run of a specific write operation: same inputs, returns what *would* happen. Always paired with the writer it previews. | `PostEarlyCheckoutCharges.preview`, `FolioRouting::ApplyBatch.preview`, `FolioRouting::PreviewExistingCharges` |

## Routing

| Verb | Means | Examples |
|---|---|---|
| `route` | Decides which folio a transaction code's charges belong to. | `FolioRouting::RouteCodeToBillingParty` |
| `apply` | Writes a change set that has already been decided and validated. The decision happened earlier; `apply` commits it. | `FolioRouting::ApplyBatch`, `FolioRouting::ApplyExistingCharges` |

## Folio lifecycle

| Verb | Means | Examples |
|---|---|---|
| `create` | A new folio, because someone explicitly asked for one. | `CreateFolio` |
| `initialize` | Sets up a booking's primary folio as a **step inside another workflow** (confirmation, check-in), not as a request in its own right. | `InitializeForBooking` |
| `recover` | Repairs something that should already exist and does not. Reactive, and expects to find nothing to do most of the time. | `RecoverMissingFolio` |
| `close` / `reopen` / `rename` / `update` | Exactly what they say. `reopen` always crosses an authorization boundary. | `CloseFolio`, `CloseForCheckout`, `ReopenFolio`, `ReopenForCorrection`, `RenameFolio`, `UpdateFolio` |

## Transaction-level corrections

`reverse`, `split`, `move` — each acts on one existing transaction and leaves an
audit trail. They never quietly rewrite history.

## Verbs to reach for last

| Verb | Means | Why last |
|---|---|---|
| `process` | A multi-step workflow over a set of things. | Usually a sign the class does several jobs. Legitimate when the steps genuinely belong to one operation (`ProcessCheckoutActions`), but check first whether a sharper verb fits. |
| `backfill` | A maintenance sweep over historical records. | Not a domain operation. Belongs in maintenance or a rake task, not beside the services staff actions call. |

## Nouns are deliberate

`PaymentSource`, `RefundSource`, `RoutePreview`, `ForecastedChargeLines`,
`RoutingMatrix`, `ChargePostingKeys`, `NextFolioNumber`,
`TransactionActionPolicy`, `RoutabilityPolicy`, `BookingCheckoutReadiness` — a
noun name means it is a query or value object, not a command. **A noun that
writes to the database is a bug in the name.**
