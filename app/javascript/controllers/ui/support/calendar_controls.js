const MOBILE_QUERY = "(max-width: 639px)"
const MONTH_NAMES = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

export function connectCalendarControls(controller) {
  controller.calendarMedia = window.matchMedia(MOBILE_QUERY)
  controller.onCalendarMediaChange = () => applyResponsiveMonths(controller)
  controller.calendarMedia.addEventListener("change", controller.onCalendarMediaChange)
  applyResponsiveMonths(controller)
  syncCaption(controller)
}

export function disconnectCalendarControls(controller) {
  controller.calendarMedia?.removeEventListener("change", controller.onCalendarMediaChange)
}

export function applyResponsiveMonths(controller) {
  if (!controller.hasCalendarTarget || !controller.hasMonthsValue) return
  const compact = controller.hasResponsiveMonthsValue && controller.responsiveMonthsValue && controller.calendarMedia?.matches
  controller.calendarTarget.setAttribute("months", String(compact ? 1 : controller.monthsValue))
  if (controller.hasMonthsTarget) controller.monthsTarget.dataset.compact = compact ? "true" : "false"
}

export function syncCaption(controller, iso = null) {
  if (!controller.hasMonthLabelTarget || !controller.hasYearLabelTarget) return
  const raw = iso || controller.calendarTarget.focusedDate || controller.calendarTarget.value?.split("/")[0]
  const date = parseISODate(raw) || new Date()
  const month = date.getUTCMonth() + 1
  const year = date.getUTCFullYear()
  controller.monthLabelTarget.textContent = MONTH_NAMES[month - 1]
  controller.yearLabelTarget.textContent = String(year)
  markSelected(controller.monthListboxTarget, String(month))
  markSelected(controller.yearListboxTarget, String(year))
}

export function toggleCaption(controller, event) {
  const kind = event.currentTarget.dataset.captionKind
  const listbox = captionListbox(controller, kind)
  const open = listbox.hidden
  closeCaptions(controller)
  listbox.hidden = !open
  event.currentTarget.setAttribute("aria-expanded", String(open))
  if (open) selectedOrFirst(listbox)?.focus()
}

export function selectCaption(controller, event) {
  const option = event.currentTarget
  if (option.getAttribute("aria-disabled") === "true") return
  const kind = option.closest("[data-caption-kind]").dataset.captionKind
  setCaptionValue(controller, kind, option.dataset.captionValue)
}

export function onCaptionTriggerKeydown(controller, event) {
  if (!["ArrowDown", "Enter", " "].includes(event.key)) return
  event.preventDefault()
  toggleCaption(controller, event)
}

export function onCaptionListboxKeydown(controller, event) {
  const options = enabledOptions(event.currentTarget)
  const index = options.indexOf(document.activeElement)
  let next = null
  if (event.key === "ArrowDown") next = options[Math.min(index + 1, options.length - 1)]
  if (event.key === "ArrowUp") next = options[Math.max(index - 1, 0)]
  if (event.key === "Home") next = options[0]
  if (event.key === "End") next = options[options.length - 1]
  if (event.key === "Escape") {
    event.preventDefault()
    closeCaptions(controller)
    return
  }
  if (next) {
    event.preventDefault()
    next.focus()
  }
}

export function closeCaptions(controller) {
  for (const kind of ["month", "year"]) {
    if (!hasCaption(controller, kind)) continue
    captionListbox(controller, kind).hidden = true
    captionButton(controller, kind).setAttribute("aria-expanded", "false")
  }
}

function setCaptionValue(controller, kind, value) {
  const current = parseISODate(controller.calendarTarget.focusedDate || controller.calendarTarget.value?.split("/")[0]) || new Date()
  const year = kind === "year" ? Number(value) : current.getUTCFullYear()
  const month = kind === "month" ? Number(value) : current.getUTCMonth() + 1
  const day = Math.min(current.getUTCDate(), new Date(Date.UTC(year, month, 0)).getUTCDate())
  const iso = `${year}-${pad(month)}-${pad(day)}`
  controller.calendarTarget.focusedDate = iso
  syncCaption(controller, iso)
  closeCaptions(controller)
  captionButton(controller, kind).focus()
}

function parseISODate(value) {
  const match = String(value || "").match(/^(\d{4})-(\d{2})-(\d{2})/)
  return match ? new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]))) : null
}

function markSelected(listbox, value) {
  listbox.querySelectorAll("[role='option']").forEach((option) => {
    option.setAttribute("aria-selected", String(option.dataset.captionValue === value))
  })
}

function enabledOptions(listbox) {
  return [...listbox.querySelectorAll("[role='option']:not([aria-disabled='true'])")]
}

function selectedOrFirst(listbox) {
  return listbox.querySelector("[aria-selected='true']:not([aria-disabled='true'])") || enabledOptions(listbox)[0]
}

function hasCaption(controller, kind) {
  return kind === "month" ? controller.hasMonthListboxTarget : controller.hasYearListboxTarget
}

function captionListbox(controller, kind) {
  return kind === "month" ? controller.monthListboxTarget : controller.yearListboxTarget
}

function captionButton(controller, kind) {
  return kind === "month" ? controller.monthButtonTarget : controller.yearButtonTarget
}

function pad(value) {
  return String(value).padStart(2, "0")
}
