// Shared, teardown-safe helpers for PanelsUI overlay primitives
// (dialog, drawer, popover, dropdown, tooltip, toast).
//
// This file is intentionally NOT named `*_controller.js`, so Stimulus's
// `lazyLoadControllersFrom("controllers")` skips it — it's a plain support module
// imported by the individual controllers.
//
// Every function that attaches listeners returns a single `cleanup()` that removes
// exactly what it added. Controllers MUST call these from `disconnect()`; that is
// the contract that keeps the primitives free of leaked listeners/observers.

import { clearAllBodyScrollLocks, disableBodyScroll } from "body-scroll-lock"
import { createFocusTrap } from "focus-trap"

// ── Scroll locking ───────────────────────────────────────────────────────────
// body-scroll-lock restores body overflow whenever enableBodyScroll is called,
// even if another target remains locked. Keep our own ordered stack and clear the
// library's locks only after the final overlay closes.
const activeOverlays = []

export function lockScroll(element) {
  if (activeOverlays.includes(element)) return

  activeOverlays.push(element)
  disableBodyScroll(element, { reserveScrollBarGap: true })
}

export function unlockScroll(element) {
  const index = activeOverlays.indexOf(element)
  if (index === -1) return

  activeOverlays.splice(index, 1)
  if (activeOverlays.length === 0) clearAllBodyScrollLocks()
}

export function isTopOverlay(element) {
  return activeOverlays.at(-1) === element
}

// No JS animation library. Controllers toggle a `data-panels-open` attribute as an
// optional styling hook — target it with CSS transitions (and prefers-reduced-motion)
// if/when a primitive wants an enter/leave effect.

// ── Focus trapping (for non-native overlays) ─────────────────────────────────
// The native <dialog> element traps focus on its own, so PanelsUI::Dialog does not
// need this; drawers/popovers that aren't native use it. Returns the trap so the
// caller can `.deactivate()` in disconnect().
export function createTrap(element, options = {}) {
  return createFocusTrap(element, {
    escapeDeactivates: false, // dismissal is owned by onDismiss below
    allowOutsideClick: true,
    fallbackFocus: element,
    ...options,
  })
}

// ── Dismissal (Escape + outside pointer) ─────────────────────────────────────
// Attaches document-level listeners and returns a cleanup() that removes them.
// Pass only the callbacks you want; omitted ones are simply not wired.
export function onDismiss(element, { onEscape, onOutside } = {}) {
  const handlers = []

  if (onEscape) {
    const keydown = (event) => {
      if (event.key === "Escape") onEscape(event)
    }
    document.addEventListener("keydown", keydown)
    handlers.push(() => document.removeEventListener("keydown", keydown))
  }

  if (onOutside) {
    const pointerdown = (event) => {
      if (!element.contains(event.target)) onOutside(event)
    }
    // capture phase so we see the click before it's swallowed by inner handlers
    document.addEventListener("pointerdown", pointerdown, true)
    handlers.push(() => document.removeEventListener("pointerdown", pointerdown, true))
  }

  return () => handlers.forEach((remove) => remove())
}
