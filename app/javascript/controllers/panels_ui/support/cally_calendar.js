// Shared support for the PanelsUI pickers that embed a Cally calendar
// (<calendar-date> / <calendar-range>). Importing this module once registers
// Cally's custom elements as a side effect.
//
// Intentionally NOT named `*_controller.js`, so Stimulus's
// `lazyLoadControllersFrom("controllers")` skips it — it's a plain support
// module imported by the date/datetime picker controllers.

import "cally"

// Apply/clear the selectable-range bounds on a <calendar-*> element. Cally
// expects ISO dates (YYYY-MM-DD); empty strings are treated as "no bound".
export function applyBounds(calendar, { min, max } = {}) {
  setAttr(calendar, "min", min)
  setAttr(calendar, "max", max)
}

function setAttr(el, name, value) {
  if (value) el.setAttribute(name, value)
  else el.removeAttribute(name)
}

// Format a Cally range value ("start/end") for display in the single-input
// range text field. Mirrors Flatpickr's default " to " separator.
export function formatRange(value, formatter = (iso) => iso) {
  if (!value) return ""

  const [start, end] = value.split("/")
  if (!start) return ""
  if (!end || end === start) return formatter(start)

  return `${formatter(start)} to ${formatter(end)}`
}
