import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { syncSelectMenu } from "controllers/panels_ui/select_menu_sync"
import { serializeForm } from "controllers/panels_ui/support/form_state"

// The rate plan page: one form split across tabs.
// - Leaving with unsaved changes (Back, sidebar, switching room category,
//   closing the tab) asks first.
// - The active tab is carried on the form's action URL so Save returns to it
//   without the tab itself counting as a change.
// - A field the browser or the server rejects is usually on another tab, so
//   the page switches to that tab instead of failing silently.
export default class extends Controller {
  static targets = ["form", "selectedRatePlanId"]
  static values = { pageUrl: String }

  connect() {
    this.pristine = this.hasFormTarget ? serializeForm(this.formTarget) : null
    this.pending = null
    this.leaving = false
    this.roomSelect = this.element.querySelector('[name="rate_plan[room_type_id]"]')
    this.roomSelectValue = this.roomSelect?.value

    this.onBeforeVisit = this.beforeVisit.bind(this)
    this.onBeforeUnload = this.beforeUnload.bind(this)
    this.onSubmitStart = () => { this.leaving = true }
    this.onSubmitEnd = (event) => { if (!event.detail.success) this.leaving = false }
    this.onTabChange = this.tabChanged.bind(this)
    this.onInvalid = this.invalid.bind(this)

    document.addEventListener("turbo:before-visit", this.onBeforeVisit)
    window.addEventListener("beforeunload", this.onBeforeUnload)
    document.addEventListener("turbo:submit-start", this.onSubmitStart)
    document.addEventListener("turbo:submit-end", this.onSubmitEnd)
    window.addEventListener("panels-ui--tabs:change", this.onTabChange)
    if (this.hasFormTarget) this.formTarget.addEventListener("invalid", this.onInvalid, true)

    this.showFirstError()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.onBeforeVisit)
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("turbo:submit-start", this.onSubmitStart)
    document.removeEventListener("turbo:submit-end", this.onSubmitEnd)
    window.removeEventListener("panels-ui--tabs:change", this.onTabChange)
    if (this.hasFormTarget) this.formTarget.removeEventListener("invalid", this.onInvalid, true)
  }

  get dirty() {
    return this.hasFormTarget && serializeForm(this.formTarget) !== this.pristine
  }

  beforeVisit(event) {
    if (this.leaving || !this.dirty) return

    event.preventDefault()
    this.confirmDiscard(event.detail.url)
  }

  beforeUnload(event) {
    if (this.leaving || !this.dirty) return

    event.preventDefault()
    event.returnValue = ""
  }

  selectRoom(event) {
    const roomTypeId = event.target.closest("select")?.value
    if (!roomTypeId) return

    const destination = new URL(this.pageUrlValue, window.location.origin)
    destination.searchParams.set("room_type_id", roomTypeId)
    destination.searchParams.set("tab", "pricing")
    Turbo.visit(destination.pathname + destination.search)
  }

  clearRatePlanSelection() {
    if (this.hasSelectedRatePlanIdTarget) this.selectedRatePlanIdTarget.value = ""
  }

  selectRatePlan(event) {
    if (this.hasSelectedRatePlanIdTarget) this.selectedRatePlanIdTarget.value = event.detail?.result?.id || ""
  }

  keepEditing() {
    this.pending = null
    this.restoreRoomSelect()
  }

  discardChanges() {
    const url = this.pending
    this.pending = null
    if (!url) return

    this.leaving = true
    requestAnimationFrame(() => Turbo.visit(url))
  }

  confirmDiscard(url) {
    this.pending = url
    const dialog = this.element.querySelector("#rate-plan-editor-discard-alert")
    if (dialog && !dialog.open) dialog.showModal()
  }

  tabChanged(event) {
    if (event.detail?.id !== "rate-plan-tabs" || !this.hasFormTarget) return

    const action = new URL(this.formTarget.action, window.location.origin)
    action.searchParams.set("tab", event.detail.name)
    this.formTarget.action = action.pathname + action.search
  }

  // The browser's own required-field check can't show its message on a
  // hidden tab, so bring the field's tab forward first.
  invalid(event) {
    if (this.invalidHandled) return

    this.invalidHandled = true
    requestAnimationFrame(() => { this.invalidHandled = false })
    this.showTabFor(event.target)
    requestAnimationFrame(() => event.target.reportValidity?.())
  }

  showFirstError() {
    const summary = this.element.querySelector("[data-rate-plan-editor-error-summary]")
    if (!summary) return

    const field = this.element.querySelector('[data-tab-panel] [aria-invalid="true"]')
    if (field) this.showTabFor(field)
    requestAnimationFrame(() => summary.focus())
  }

  showTabFor(element) {
    const name = element.closest("[data-tab-panel]")?.dataset.tabPanel
    if (!name) return

    const tab = this.element.querySelector(`[role="tab"][data-tab-name="${name}"]`)
    if (tab && tab.getAttribute("aria-selected") !== "true") tab.click()
  }

  restoreRoomSelect() {
    if (!this.roomSelect || this.roomSelect.value === this.roomSelectValue) return

    this.roomSelect.value = this.roomSelectValue
    syncSelectMenu(this.application, this.roomSelect)
  }
}
