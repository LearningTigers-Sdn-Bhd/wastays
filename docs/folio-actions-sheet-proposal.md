# Folio Actions — Sheet family proposal

Move every folio action off the legacy Offcanvas drawer onto a `PanelsUI::Sheet`
family that mirrors `HotelPortal::Bookings::Actions`.

Folio actions are their **own** family. They copy the booking-actions conventions
but share none of its frames, concerns, helpers, or names — the same isolation
`BookingActionCompletion` was given from `OffcanvasTransactionCompletion`.

## Conventions inherited from booking actions

| Layer | Convention |
|---|---|
| Routing | One flat scope, verb-named URLs, `match … via: [:get, <write verb>]` |
| Controller | One per action. `def show; return create if request.post?; render :show, layout: false; end` |
| Base | Authorize → set records → set `@return_to`. Exposes `complete_action(notice:/alert:)` |
| View | `show.html.erb` = `turbo_frame_tag(turbo_frame_request_id.presence \|\| "folio_action_sheet")` wrapping `_form` |
| Completion | `complete_sheet` stream targeting the requesting frame; JS closes the dialog then navigates |
| Return | `return_to` hidden field, validated same-origin + `/hotel/<slug>/` prefix |
| Confirmations | `size: :sm` sheet with a destructive submit — not a Dialog |

## Reused unchanged — no new JavaScript

`Turbo.StreamActions.complete_sheet` already reads its frame from the `target`
attribute; `panels-ui--sheet-frame` clears whatever frame encloses it. Both are
generic. `PanelsUI::Sheet` is used as-is.

## New surface

- `config/routes.rb` — `scope "folio-actions", as: :folio_action, module: "folios/actions"`
- `app/controllers/concerns/folio_action_completion.rb`
- `app/controllers/hotel_portal/folios/actions/base_controller.rb`
- 9 action controllers under `folios/actions/`
- `folio_action_sheet` + `folio_action_sheet_secondary` frames in `_hotel_shell.html.erb`

## Routes

```ruby
scope "folio-actions", as: :folio_action, module: "folios/actions" do
  match "post-transaction/:booking_id",                         to: "transactions#show",               via: [ :get, :post ],  as: :post_transaction
  match "move-transaction/:booking_id/:transaction_id",         to: "transaction_moves#show",          via: [ :get, :post ],  as: :move_transaction
  match "split-transaction/:booking_id/:transaction_id",        to: "transaction_splits#show",         via: [ :get, :post ],  as: :split_transaction
  match "reverse-transaction/:booking_id/:transaction_id",      to: "transaction_reversals#show",      via: [ :get, :post ],  as: :reverse_transaction
  match "new-window/:booking_id",                               to: "windows#show",                    via: [ :get, :post ],  as: :new_window
  match "edit-window/:booking_id/:folio_id",                    to: "windows#show",                    via: [ :get, :patch ], as: :edit_window
  match "close-window/:booking_id/:folio_id",                   to: "window_closures#show",            via: [ :get, :post ],  as: :close_window
  match "reopen-window/:booking_id/:folio_id",                  to: "window_reopenings#show",          via: [ :get, :post ],  as: :reopen_window
  match "billing-routes/:booking_id",                           to: "billing_routes#show",             via: [ :get, :post ], as: :billing_routes
  match "group-billing-routes/:booking_id",                     to: "group_billing_routes#show",       via: [ :get, :post ], as: :group_billing_routes
end
```

`booking_id` in the path is correct, not a leftover: folios are addressed by
booking (`resources :folios, param: :booking_id`). There is no top-level
`/folios/:folio_id`.

## Base controller

```ruby
module HotelPortal
  module Folios
    module Actions
      class BaseController < HotelPortal::BaseController
        include FolioActionCompletion

        before_action :authorize_view_bookings!
        before_action :authorize_folio_action!
        before_action :set_booking
        before_action :set_return_to

        private

        # Folio permissions are per-verb, and posting derives its slug from
        # transaction_type + category, so the base cannot name one slug.
        def authorize_folio_action!
          permit_folio!("manage_folio_windows")
        end

        def permit_folio!(slug)
          allowed = (current_user.respond_to?(:superadmin?) && current_user.superadmin?) ||
                    current_user.has_permission?(slug, hotel: current_hotel)
          raise Pundit::NotAuthorizedError unless allowed
        end

        def set_booking
          @booking = current_hotel.bookings.find(params[:booking_id])
        end

        def set_return_to
          @return_to = folio_action_return_to(fallback: hotel_folio_path(current_hotel, @booking))
        end

        def requesting_sheet_frame
          turbo_frame_request_id.presence || "folio_action_sheet"
        end

        def complete_action(notice: nil, alert: nil)
          return complete_folio_action(destination: @return_to, notice: notice, frame: requesting_sheet_frame) if alert.blank?

          respond_to do |format|
            format.turbo_stream do
              flash[:alert] = alert
              render_folio_action_completion(@return_to, frame: requesting_sheet_frame)
            end
            format.html { redirect_to @return_to, alert: alert, status: :see_other }
          end
        end
      end
    end
  end
end
```

## Action map

| Route | Verbs | Permission | Sheet | Replaces |
|---|---|---|---|---|
| `post-transaction` | GET/POST | computed (see below) | `:right, :lg` | `folios/transactions/{offcanvas,_sheet}` |
| `move-transaction` | GET/POST | `manage_folio_movements` | `:right, :lg` | `folios/transactions/move/{offcanvas,_sheet}` |
| `split-transaction` | GET/POST | `manage_folio_movements` | `:right, :md` | inline Dialog in `_ledger_desktop_row` |
| `reverse-transaction` | GET/POST | `post_folio_corrections` (+ override) — **stays in the action body**, see below | `:right, :md` | inline Dialog in `_ledger_desktop_row` |
| `new-window` | GET/POST | `manage_folio_windows` | `:right, :lg` | `folios/manage_windows/{offcanvas,_sheet}` |
| `edit-window` | GET/PATCH | `manage_folio_windows` | `:right, :lg` | same, + duplicate in `WorkspaceActionsController` |
| `close-window` | GET/POST | `manage_folio_windows` | `:right, :sm` | raw `<dialog>` (folio page) + `PanelsUI::Dialog` (workspace) |
| `reopen-window` | GET/POST | `manage_folio_windows` | `:right, :sm` | same |
| `billing-routes` | GET/POST | `manage_folio_movements` | `:right, :xl` | staged selective workflow in `WorkspaceActionsController` |
| `group-billing-routes` | GET/POST | `manage_folio_movements` | `:bottom, :full` | staged group workflow in `WorkspaceActionsController` |

Both billing-route POST endpoints dispatch through a hidden `workflow_step` of
`preview` or `apply`. The existing `Folios::Routing::ApplyBatch` and
`ApplyGroupBatch` services remain canonical: they retain impact review,
automatic application when review is unnecessary, tax and forecast choices,
idempotency, rollback, and group-child scoping. Unknown workflow steps render
the requesting Sheet with status `422`.

### Where folio permissions live today

| Action | Slug | Enforced |
|---|---|---|
| `reverse` | `post_folio_corrections`, + `PostingGuard::OVERRIDE_PERMISSION` for a closed folio or closed business date | Controller, via `Folios::Transactions::TransactionActionPolicy#reverse_allowed?` |
| `move` | `manage_folio_movements` (`MoveTransaction::PERMISSION`) | Service. Controller checks only on GET (`move_form`) |
| `split` | `manage_folio_movements` (`SplitTransaction::PERMISSION`) | Service only — no controller check |
| windows | `manage_folio_windows` | Controller `before_action` |
| billing routes | `manage_folio_movements` | Controller `before_action` |
| posting | computed, see below | Controller, two divergent derivations |

Move and split are gated in the service, so a direct POST reaches the service
before any controller check. `authorize_folio_action!` gives them a
controller-side gate and makes GET and POST symmetric — defence in depth, not a
replacement for the service check.

### Reverse does not use the authorize hook

`reverse_allowed?` is one boolean over a list that mixes authorization with
business state — "you lack `post_folio_corrections`" sits alongside "this is a
night audit row", "gateway payments use the refund workflow", "already
reversed". A `before_action` raising `Pundit::NotAuthorizedError` cannot express
that: a night-audit row would 403 instead of returning its explanation.

So `TransactionReversalsController` overrides `authorize_folio_action!` to a
no-op and keeps the policy check in the action body, completing with
`complete_action(alert: policy.reverse_error)`. Splitting the policy into
separate permission and state predicates is a bigger change; out of scope here.

### Computed posting permission

`FOLIO_POSTING_PERMISSIONS` maps 11 `[transaction_type, category]` pairs to 6
slugs (`post_folio_charges`, `post_folio_payments`, `execute_folio_refunds`,
`post_folio_adjustments`, `post_folio_corrections`, `post_folio_write_offs`).

Today GET and POST derive it from **different sources** —
`allowed_to_view_posting_sheet?` reads `@transaction_type`/`@category` from the
query string, `posting_permission_slug` reads them from `folio_transaction`
params. Collapse to one derivation during the move; the divergence is a latent
authorization gap.

## Naming migration

Every action uses a three-line `show.html.erb` frame wrapper which renders an
action-local `_form` partial. There is no shared Sheet partial or second view
abstraction.

| Current | New |
|---|---|
| `_sheet.html.erb` (×4) | `_form.html.erb` |
| `@sheet_title`, `@sheet_description` | `@form_title`, `@form_description` |
| `assign_sheet_config` | `assign_form_config` |
| `sheet_folio` | `target_folio` |
| `allowed_to_view_posting_sheet?` | folded into the single permission derivation |
| `folio_origin`, `redirect_to_folio` | `return_to` |

Replacing `folio_origin`/`redirect_to_folio` with a validated `return_to` deletes
the three-branch `redirect_after_post` and two hidden fields from every folio form.

## Consequences

- `FolioTransactionsController` empties completely.
- `FoliosController` keeps `index`/`show`/`invoice`/`ledger`; the redirect-only
  `Folios::RoutingRulesController` and its obsolete routes/views are removed.
- `WorkspaceActionsController` loses duplicated folio-window actions and both
  staged billing-route workflows.
- Split and reverse stop rendering a full Dialog **per ledger row** — they become
  lazily fetched, removing N dialogs from the folio page DOM.
- All routing launchers target `folio_action_sheet`. The nested "Add folio"
  launch from inside billing routes remains a plain
  `folio_action_sheet_secondary` target; the offcanvas controller's
  `navigatingInsideOpenDrawer` special case disappears.
- `offcanvas_controller.js` still cannot be deleted — taxes_fees, room_groups,
  corporate_accounts, transaction_codes, and guest-registration templates use it.

## Completion navigation

`complete_sheet` deliberately retains `window.location.assign`. Progressed
folio actions need a full reload so the Stay View, folio balances, routing
matrix, and related frames cannot remain stale after completion.

## Specs to rewrite

`spec/requests/hotel_portal/folios_spec.rb`,
`spec/requests/hotel_portal/folio_transactions_spec.rb`,
`spec/requests/hotel_portal/folios/actions/billing_routes_spec.rb`,
`spec/requests/hotel_portal/bookings/workspace_actions_spec.rb`,
`spec/system/hotel/folio_operations_ledger_spec.rb`,
`spec/requests/hotel_portal/bookings/workspaces_spec.rb`.

Target assertion shape, from the booking-action specs:

```ruby
document.at_css("turbo-frame#folio_action_sheet dialog#<id>[data-controller='panels-ui--sheet']")
expect(response.body).not_to include("offcanvas")
```
