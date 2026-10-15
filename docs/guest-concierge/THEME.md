# GuestUI Theme Contract

Status: Decided. This document authorizes implementation.

## Purpose

GuestUI provides one visual system for these guest-facing products:

- Public Concierge.
- The locked stay page.
- Checked-in Concierge.
- The Guest Portal.

GuestUI and PanelsUI use the same semantic token names. Each theme supplies different values for those names.

## Theme Boundary

Guest-facing layouts use this explicit theme:

```html
<body data-theme="guest">
```

The guest theme must not own `:root`. A guest color must not become the accidental default for another product.

PanelsUI retains its existing panel themes. GuestUI must not use a panel theme to obtain guest colors.

## Theme Location

The GuestUI values belong directly in the guest theme file:

```text
app/assets/tailwind/guest/theme.css
```

Do not create a separate `tokens.css` file. Do not add another abstraction layer for the shared token names.

## Shared Semantic Names

GuestUI must use the established semantic names from PanelsUI where the meaning is the same.

### Base surfaces

```css
--background
--foreground
--card
--card-foreground
--muted
--muted-foreground
```

### Primary and secondary actions

```css
--primary
--primary-hover
--primary-active
--primary-foreground
--secondary
--secondary-foreground
--accent
--accent-foreground
```

### Interaction boundaries

```css
--border
--border-interactive
--ring
```

### Feedback colors

```css
--destructive
--destructive-foreground
--destructive-on-surface
--warning
--warning-foreground
--warning-on-surface
--success
--success-foreground
--success-on-surface
--info
--info-foreground
--info-on-surface
```

### Status surfaces

GuestUI can use the existing status-name pattern when a guest component needs that state:

```css
--status-neutral-background
--status-neutral-foreground
--status-neutral-border
--status-neutral-indicator
```

The same pattern applies to `primary`, `accent`, `info`, `success`, `warning`, and `destructive` statuses.

### Shadows

```css
--shadow-color
--shadow-sm
--shadow-base
--shadow-lg
```

## Different Theme Values

The semantic role stays consistent across the products. The visual value changes with the theme.

| Token role | PanelsUI direction | GuestUI direction |
| --- | --- | --- |
| `background` | Cool operational surface | Warm hospitality surface |
| `foreground` | Operational dark green | Softer guest-facing ink |
| `card` | Clean workspace surface | Warm elevated surface |
| `primary` | Interactive operational teal | Deep hotel green |
| `accent` | Operational highlight | Restrained champagne highlight |
| `border` | Clear structural division | Softer guest-facing division |
| `shadow-base` | Restrained workspace depth | Softer hospitality depth |

This table defines the direction only. Exact color values require separate visual approval.

## Naming Rules

Every token name must describe a reusable visual role.

Use names such as:

- `background`.
- `card`.
- `primary`.
- `muted-foreground`.
- `border-interactive`.
- `status-success-background`.

Do not use names such as:

- `guest-green`.
- `warm-box`.
- `fancy-gold`.
- `dark-green-2`.
- `color-1`.
- `concierge-card-color`.

Do not add a `guest-` prefix to an established semantic token. The `[data-theme="guest"]` scope already identifies the theme.

## New Token Rule

Add a new token only when all these statements are true:

- No established token describes the role.
- More than one component uses the role.
- The name describes purpose instead of appearance.
- The role remains meaningful when its color changes.

Keep a component-only value inside that component. Do not promote every local value into the theme.

## Component Use

GuestUI components must use semantic utilities or semantic CSS variables.

Correct:

```html
<section class="border-border bg-card text-card-foreground">
  <button class="bg-primary text-primary-foreground">Request towels</button>
</section>
```

Incorrect:

```html
<section class="border-[#e5ded1] bg-[#fffdf8] text-slate-900">
  <button class="bg-brand-primary text-white">Request towels</button>
</section>
```

GuestUI and PanelsUI can use different component geometry. Shared token names do not require shared ViewComponents or identical styling.

## Component Ownership

PanelsUI remains the component system for operational portals. GuestUI becomes the component system for guest-facing product flows.

The existing PublicUI components can move into GuestUI. Do not create overlapping PublicUI and GuestUI primitives for the same role.

Shared technical foundations can include:

- `TailwindVariants`.
- `app_icon`.
- Turbo behavior.
- Stimulus behavior.
- Common accessibility utilities.

Visual primitives remain owned by their product component system.

## Typography

GuestUI keeps the existing font families until a separate decision changes them.

The guest typography system has these roles:

- A restrained display role for hotel names and major stay moments.
- A sans-serif body role for actions, details, forms, and navigation.
- A clear data treatment for dates, times, room numbers, and confirmation codes.

Components must use role-based type styles. Pages must not invent unrelated local type scales.

## Accessibility

Every approved guest-theme value must support WCAG 2.2 AA contrast.

The contrast review must include:

- Normal and large text.
- Buttons and interactive boundaries.
- Focus rings.
- Error and status text.
- Text over hotel photographs.
- Disabled states.

Color must not be the only way that the interface communicates state.

## Decisions

| Question | Decision |
| --- | --- |
| Dark theme | No. The first delivery is light only |
| Typography scale | Reuse the PanelsUI scale |
| Radius and shadow scale | Reuse the PanelsUI scale |
| Guest-specific roles | None. A new role needs a new discussion |

## Open Decisions

One item remains open:

- The exact guest-theme color values.

The color values are the only new visual decision. Everything else comes from PanelsUI.
