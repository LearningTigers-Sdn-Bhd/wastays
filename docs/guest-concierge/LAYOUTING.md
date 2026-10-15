# GuestUI Layout Contract

Status: Decided. This document authorizes implementation.

## Purpose

This document defines the shared page structure for Public Concierge, Checked-in Concierge, and related GuestUI pages.

The layouts share one design system. Each page still follows its own content and authorization scope.

## Shared Hotel Hero

Every hotel-scoped Concierge page starts with the full-width hotel hero.

The hero provides:

- The hotel photograph.
- The hotel name.
- The hotel location.
- Relevant global guest actions.

The desktop hero remains above the content. It does not become a permanent left column.

The hero height must stay controlled. It must not consume most of the desktop viewport.

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                                                                              │
│                          [ HOTEL PHOTOGRAPH ]                                │
│                                                                              │
│  Sandbay Hotel                                           Contact   Chat      │
│  Kota Kinabalu                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

## Desktop Structure

The authenticated desktop page uses two rows.

### Row 1

Row 1 contains the full-width hotel hero.

### Row 2

Row 2 uses two content columns inside one centered container:

- Column 1 contains stable stay details.
- Column 2 contains actions and hotel services.

Column 1 uses approximately one-third of the available width. Column 2 uses approximately two-thirds.

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                              HOTEL HERO                                      │
└──────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────┐  ┌─────────────────────────────────────────────┐
│                            │  │                                             │
│  STAY DETAILS              │  │  ACTIONS AND HOTEL SERVICES                 │
│                            │  │                                             │
│  Stable booking facts      │  │  Current guest tasks                        │
│  Stay dates                │  │  Service requests                           │
│  Room information          │  │  Hotel information                          │
│  Check-out time            │  │  Contact and chat                           │
│  Booking documents         │  │  Check-out action                           │
│                            │  │                                             │
└────────────────────────────┘  └─────────────────────────────────────────────┘
```

The left column is not a navigation sidebar. It contains information about the current stay only.

The right column owns the primary task flow. It can grow vertically without changing the stay-information hierarchy.

## Checked-in Concierge Desktop

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                          [ HOTEL PHOTOGRAPH ]                                │
│  Sandbay Hotel · Kota Kinabalu                           Contact   Chat      │
└──────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────┐  ┌─────────────────────────────────────────────┐
│  YOUR STAY                 │  │  Good afternoon, Nadia                      │
│                            │  │                                             │
│  Room 503                  │  │  What do you need?                          │
│  21 Sep — 24 Sep           │  │                                             │
│  3 nights                  │  │  ┌──────────────┐  ┌──────────────┐         │
│                            │  │  │ Housekeeping │  │ Request item │         │
│  Check-out                 │  │  └──────────────┘  └──────────────┘         │
│  24 Sep · 11:00 AM         │  │                                             │
│                            │  │  Do not disturb                    Off       │
│  Booking WS-ABC123         │  │                                             │
│                            │  │  Wi-Fi and hotel information             ›  │
│  View stay details         │  │  Recommendations and offers             ›  │
│  Invoice                   │  │  Contact the front desk                 ›  │
│  Request check-out         │  │  Chat with us                            ›  │
└────────────────────────────┘  └─────────────────────────────────────────────┘
```

The left column answers, “What is my stay?” The right column answers, “What can I do?”

## Locked Stay Desktop

The locked page keeps the same hero and two-column structure. It does not show stay facts before device verification.

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                          [ HOTEL PHOTOGRAPH ]                                │
│  Sandbay Hotel · Kota Kinabalu                                              │
└──────────────────────────────────────────────────────────────────────────────┘

┌────────────────────────────┐  ┌─────────────────────────────────────────────┐
│  ABOUT THIS ACCESS         │  │  Open your stay                             │
│                            │  │                                             │
│  This link gives access    │  │  Booking confirmation code                  │
│  to one hotel stay.        │  │  ┌───────────────────────────────────────┐  │
│                            │  │  │ WS-                                   │  │
│  Stay facts remain hidden  │  │  └───────────────────────────────────────┘  │
│  before verification.      │  │                                             │
│                            │  │  [ Verify this device ]                     │
└────────────────────────────┘  └─────────────────────────────────────────────┘
```

## Public Concierge Desktop

Public Concierge has no stay-details column. It uses one centered action region below the hero.

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                          [ HOTEL PHOTOGRAPH ]                                │
│  Sandbay Hotel · Kota Kinabalu                                              │
└──────────────────────────────────────────────────────────────────────────────┘

                 How can we help?

                 Check in       Check out

                 Request something                                      ›
                 Recommendations                                        ›
                 Contact the hotel                                      ›
                 Chat with us                                           ›
```

Do not render an empty left column on a public page.

## Mobile Structure

Mobile keeps the same information order and stacks the content columns.

```text
┌───────────────────────────┐
│        HOTEL HERO         │
└───────────────────────────┘

┌───────────────────────────┐
│       STAY DETAILS        │
└───────────────────────────┘

┌───────────────────────────┐
│    ACTIONS AND SERVICES   │
└───────────────────────────┘
```

The stay details appear before the action list. This order gives the guest context before the guest acts.

Primary touch targets must remain at least 44 by 44 CSS pixels.

## Guest Portal Layout

The Guest Portal uses the GuestUI theme and components. It does not copy the staff portal shell.

The Guest Portal booking index is not scoped to one hotel. It uses a WAStays header and a guest booking collection.

A hotel-scoped booking show page can use the hotel hero and the two-row layout. Its authorization remains the Guest Portal session.

The Guest Portal must not use these staff-facing patterns as its default shell:

- A permanent operational sidebar.
- A command palette.
- Dashboard metric cards.
- Dense operational tables.

The same design system does not require every guest page to use the same composition.

## Action Region

The action region orders content by guest urgency and frequency.

It can contain:

- Primary stay actions.
- Stay controls.
- Service-request entry points.
- Hotel information.
- Contact and chat actions.
- Booking documents.
- Check-out actions.

Do not make every action an equal card. Use size, placement, and grouping to show priority.

## Width and Spacing

The hero can use the full viewport width. The content below it uses one centered maximum width.

The two columns must align at the top. Their spacing must follow the GuestUI spacing scale after that scale receives approval.

Do not add page-specific maximum widths when the shared GuestUI shell can own the measure.

## Scroll Behavior

The complete page scrolls as one document. The hero does not remain as a permanent side panel.

Do not add an internal scrollbar to the stay-details or action columns. Chat can own its own viewport behavior.

## Responsive Behavior

The layout changes from one column to two columns at the approved desktop breakpoint.

Before the desktop breakpoint:

- The hero remains full-width.
- The stay details appear first.
- The action region appears second.
- Long labels wrap without reducing the type size.
- Controls remain usable with the mobile keyboard.

At the desktop breakpoint:

- The hero stays above both columns.
- The details column remains narrower.
- The action column receives the remaining width.
- The page does not become a permanent split-screen layout.

## Accessibility

The DOM order must match the mobile reading order:

1. Hotel hero.
2. Stay context or access explanation.
3. Primary actions.
4. Secondary services.
5. Supporting booking actions.

CSS grid can place the sections into columns on desktop. It must not change the reading or focus order.

## Prototype Status

The stay page is built. The markup is a prototype, not a contract.

It uses the Public Concierge shared partials and hand-written Tailwind classes,
because no page under `app/views/public/concierge/` uses PanelsUI. It adds no
component and no color token.

The structure in this document is implemented:

- The full-width hotel hero in Row 1.
- Two columns in Row 2, at about one third and two thirds.
- One column on mobile, with the stay details before the actions.
- A DOM order that matches the mobile reading order.
- Touch targets of at least 44 CSS pixels.

A later session owns the visual system. That session can rebuild the markup. The
page rules live in `Public::Concierge::StayPresenter`, not in the views, so a
rebuild does not move a rule.

## Decisions

These numbers get decided during implementation, with real content on screen:

- The maximum width of the content container.
- The exact desktop breakpoint.
- The final hero heights for mobile and desktop.
- Whether the stay-details column becomes sticky within Row 2.
- The exact action priority and grouping.

The structure in this document is the contract. The numbers are not.

The Guest Portal booking-index composition stays out of scope. The stay page does not change it.
