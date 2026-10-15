// Worked example for a long-stay discount rule. Mirrors RatePlanStayDiscount#apply:
// percent or a fixed amount off each discounted night, never below zero, rounded
// to cents. Shared by the inline row example and the "Add discount" wizard's
// simulator so both ever compute (and draw) the client-side preview one way.
export function round(amount) {
  return Math.round(amount * 100) / 100
}

export function money(amount, currency) {
  const rounded = round(amount)
  const digits = Number.isInteger(rounded) ? 0 : 2
  return `${currency} ${rounded.toLocaleString("en", { minimumFractionDigits: digits, maximumFractionDigits: 2 })}`
}

const PLACEHOLDER = "Enter the nights and the discount to see an example."

// A rule only ever has two price "runs" — full-price nights, then discounted
// ones — so above this length a night-by-night list is long without saying
// anything a range doesn't already say. Below it, spelling out every night is
// clearer than a range.
const NIGHT_BY_NIGHT_LIMIT = 7

function nightLabel(first, last) {
  return first === last ? `Night ${first}` : `Nights ${first}–${last}`
}

// Returns null when the rule isn't complete enough to preview yet, otherwise
// { heading, rows: [{ night, normal, discounted, discountApplies }], total: { nights, normal, discounted, saved } }.
export function stayDiscountExample({ nights, percent, value, fromNight, price, currency, perPerson }) {
  const clampedFromNight = Math.min(fromNight || 1, nights || 1)
  if (!(nights >= 2) || !(value > 0) || (percent && value > 100)) return null

  const discounted = round(Math.max(percent ? price * (1 - value / 100) : price - value, 0))
  const fullNights = clampedFromNight - 1
  const discountedNights = nights - fullNights
  const normalTotal = price * nights
  const total = price * fullNights + discounted * discountedNights

  const rows = nights <= NIGHT_BY_NIGHT_LIMIT
    // One row per night, so the guest can see exactly which nights get the discount.
    ? Array.from({ length: nights }, (_, index) => {
        const night = index + 1
        const discountApplies = night >= clampedFromNight
        return {
          night: `Night ${night}`,
          normal: money(price, currency),
          discounted: money(discountApplies ? discounted : price, currency),
          discountApplies
        }
      })
    // Longer stays only ever have these two runs — group them instead of
    // listing every night.
    : [
        fullNights > 0 && { night: nightLabel(1, fullNights), normal: money(price, currency), discounted: money(price, currency), discountApplies: false },
        { night: nightLabel(clampedFromNight, nights), normal: money(price, currency), discounted: money(discounted, currency), discountApplies: true }
      ].filter(Boolean)

  const guest = perPerson ? " for 1 guest" : ""
  return {
    heading: `Example: a ${nights}-night stay${guest} at ${money(price, currency)} a night`,
    rows,
    total: {
      nights: `Total (${nights} nights)`,
      normal: money(normalTotal, currency),
      discounted: money(total, currency),
      saved: `Guest saves ${money(normalTotal - total, currency)}`
    }
  }
}

// Draws the example into `heading` + `body` as a small comparison table, or the
// placeholder while the rule is incomplete.
export function renderStayDiscountExample(example, { heading, body }) {
  if (!example) {
    heading.textContent = "Example"
    body.replaceChildren(Object.assign(document.createElement("p"), { className: "mt-1", textContent: PLACEHOLDER }))
    return
  }

  heading.textContent = example.heading

  const table = document.createElement("table")
  table.className = "w-full text-left text-xs tabular-nums"

  const head = table.createTHead().insertRow()
  ;["Night", "Normal price", "With discount"].forEach((text, index) => {
    const cell = document.createElement("th")
    cell.scope = "col"
    cell.className = `sticky top-0 border-b border-border bg-inherit pb-1.5 font-medium text-muted-foreground ${index > 0 ? "text-right" : ""}`
    cell.textContent = text
    head.append(cell)
  })

  const tbody = table.createTBody()
  example.rows.forEach((row) => {
    const tr = tbody.insertRow()
    addCell(tr, row.night, "th", "py-1.5 font-normal text-foreground")
    addCell(tr, row.normal, "td", "py-1.5 text-right text-muted-foreground")
    addCell(tr, row.discountApplies ? row.discounted : `${row.discounted} (full price)`, "td",
      `py-1.5 text-right ${row.discountApplies ? "font-medium text-foreground" : "text-muted-foreground"}`)
  })

  const foot = table.createTFoot().insertRow()
  addCell(foot, example.total.nights, "th", "border-t border-border pt-1.5 font-semibold text-foreground")
  addCell(foot, example.total.normal, "td", "border-t border-border pt-1.5 text-right text-muted-foreground line-through")
  addCell(foot, example.total.discounted, "td", "border-t border-border pt-1.5 text-right font-semibold text-foreground")

  // A safety net, not the normal case: the rows above are already capped at
  // NIGHT_BY_NIGHT_LIMIT (grouped into ranges past that), so this scrolls only
  // if that ever changes.
  const scrollArea = document.createElement("div")
  scrollArea.className = "mt-2 max-h-48 overflow-y-auto"
  scrollArea.append(table)

  const saved = Object.assign(document.createElement("p"), {
    className: "mt-2 text-xs font-medium text-success",
    textContent: example.total.saved
  })

  body.replaceChildren(scrollArea, saved)
}

function addCell(row, text, tag, className) {
  const cell = document.createElement(tag)
  if (tag === "th") cell.scope = "row"
  cell.className = className
  cell.textContent = text
  row.append(cell)
}
