# Compact Hotel Sidebar Design

## Goal

Make the hotel portal sidebar easier to scan by reducing top-level clutter and grouping navigation around hotel staff tasks. The sidebar should stay friendly for first-time users: important daily workflows remain easy to find, while lower-frequency areas move behind clear dropdown groups.

## Current Context

The hotel sidebar is rendered from `HotelPortal::NavigationHelper#hotel_sidebar_sections` and displayed by `app/views/shared/navigation/_hotel_sidebar.html.erb`. It already supports:

- Section labels.
- Parent items with dropdown children via `details` and `summary`.
- Permission and plan-feature filtering.
- Active-route expansion.
- Desktop collapsed rail with tooltip and flyout behavior.
- Mobile sidebar using the same rendered nav HTML.

The main problem is information architecture, not missing mechanics. The existing sidebar has many top-level sections (`Home`, `Operations`, `Property`, `Finance`, `Team Management`, `Reports`, `System`) and too many direct links under some sections.

## Recommended Grouping

Replace current section-heavy structure with task-based dropdown groups.

### Stay View

Daily front-desk status and movement.

- Dashboard
- Arrivals
- In-House Guest
- Today's Check-Outs
- Room Status

### Reservations

Booking and guest workflow.

- Bookings
- Booking Timeline Board
- Guest Records
- Requests

### Rates & Availability

Inventory, rooms, and sellable configuration.

- Rates & Inventory
- Room Categories
- Taxes & Fees
- Transaction Codes

### Guest Experience

Guest-facing hotel content.

- Nearby Attractions
- Knowledge

### Cashiering

Money movement and guest/corporate balances.

- Folios
- Accounts Receivable
- Payouts

### Reports

Reporting and audit workflows.

- Financial
- Tax & Compliance
- Audit

### Settings

Admin, account, and system configuration.

- Hotel Details
- Staff Management
- Roles & Permissions
- Accounting
- Operation Logs
- Notification Logs
- Your Plan

## Behavior

- Each top-level task group is a dropdown.
- Active group opens automatically using existing active-route logic.
- Existing child dropdowns remain for deeper areas such as `Knowledge`, `Accounts Receivable`, `Financial`, `Tax & Compliance`, `Audit`, and `Accounting`.
- Do not duplicate links across groups in this phase. `Room Status` belongs under `Stay View`; `Requests` belongs under `Reservations`.
- Desktop collapsed rail keeps current icon-only behavior with tooltip and flyout children.
- Mobile uses the same grouped structure, avoiding a separate navigation model.

## UX Rationale

- `Stay View` gives first-time front-desk users a clear starting point for today's work.
- `Reservations` separates booking actions from live-stay status.
- `Rates & Availability` matches the sample pattern and groups revenue-control setup in one predictable place.
- `Cashiering` is clearer than broad `Finance` for operational hotel staff.
- `Settings` absorbs team, property admin, accounting setup, logs, and plan management so low-frequency admin pages no longer compete with daily workflows.
- Avoiding duplicate links prevents confusion and keeps active-state behavior simple.

## Implementation Notes

- Change grouping primarily in `app/helpers/hotel_portal/navigation_helper.rb`.
- Preserve existing `NavSection` and `NavItem` structs to keep the change small.
- Use parent `NavItem` entries with children for the new task groups where needed.
- Keep existing permission, plan feature, search text, and active checks on moved items.
- Adjust tests that assert old section labels or spacing if needed.

## Testing

- Update or add helper/system coverage for the new hotel sidebar grouping.
- Verify active child pages open the correct parent group.
- Verify collapsed sidebar flyouts still work for nested groups.
- Verify mobile sidebar renders the same grouping.
