import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { syncSelectMenu } from "controllers/panels_ui/select_menu_sync"

export default class extends Controller {
  static targets = ["form", "selectedRatePlanId"]
  static values = { editUrl: String, roomTypeId: Number }

  connect() {
    this.pristine = new Map(this.formTargets.map((form) => [form, this.serialize(form)]))
    this.pending = null
    this.submitting = false
    this.boundDocumentClick = this.documentClick.bind(this)
    this.boundSubmit = () => { this.submitting = true }
    this.roomSelect = this.element.querySelector('[name="rate_plan[room_type_id]"]')
    this.roomSelectValue = this.roomSelect?.value
    document.addEventListener("click", this.boundDocumentClick, true)
    this.element.addEventListener("submit", this.boundSubmit, true)
    this.focusErrors()
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick, true)
    this.element.removeEventListener("submit", this.boundSubmit, true)
  }

  documentClick(event) {
    if (this.submitting || !this.currentFormDirty) return

    const guarded = event.target.closest("[data-rate-plan-editor-room-url], [data-rate-plan-editor-guard]")
    if (!guarded) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.confirmDiscard({ type: "click", element: guarded })
  }

  selectRoom(event) {
    const select = event.target.closest("select")
    const roomTypeId = select?.value
    if (!roomTypeId) return

    const destination = new URL(this.editUrlValue, window.location.origin)
    destination.searchParams.set("room_type_id", roomTypeId)
    const url = destination.pathname + destination.search

    if (this.currentFormDirty) {
      this.restoreRoomSelect()
      this.confirmDiscard({ type: "visit", url })
    } else {
      Turbo.visit(url, { frame: "settings_action_sheet" })
    }
  }

  clearRatePlanSelection() {
    if (this.hasSelectedRatePlanIdTarget) this.selectedRatePlanIdTarget.value = ""
  }

  selectRatePlan(event) {
    if (!this.hasSelectedRatePlanIdTarget) return

    this.selectedRatePlanIdTarget.value = event.detail?.result?.id || ""
  }

  requestClose() {
    if (this.currentFormDirty) {
      this.confirmDiscard({ type: "close" })
    } else {
      this.closeSheet()
    }
  }

  keepEditing() {
    this.pending = null
    this.restoreRoomSelect()
  }

  discardChanges() {
    const pending = this.pending
    this.pending = null
    this.submitting = true

    requestAnimationFrame(() => {
      try {
        if (pending?.type === "close") return this.closeSheet()
        if (pending?.type === "visit") return Turbo.visit(pending.url, { frame: "settings_action_sheet" })
        if (pending?.type === "click") pending.element?.click()
      } finally {
        // A navigation replaces this controller, so the reset only matters when
        // one never happened — without it the dirty guard stays off for good.
        this.submitting = false
      }
    })
  }

  confirmDiscard(pending) {
    this.pending = pending
    const dialog = this.element.querySelector("#rate-plan-editor-discard-alert")
    if (dialog && !dialog.open) dialog.showModal()
  }

  get currentForm() {
    return this.formTargets[0] || null
  }

  get currentFormDirty() {
    const form = this.currentForm
    return Boolean(form) && this.serialize(form) !== this.pristine.get(form)
  }

  serialize(form) {
    return Array.from(new FormData(form).entries())
      .map(([key, value]) => [key, value instanceof File ? `${value.name}:${value.size}` : String(value)])
      .sort(([aKey, aValue], [bKey, bValue]) => `${aKey}:${aValue}`.localeCompare(`${bKey}:${bValue}`))
      .map(([key, value]) => `${key}=${value}`)
      .join("&")
  }

  closeSheet() {
    const dialog = this.element.querySelector("#edit-rate-plan-sheet, #new-rate-plan-sheet")
    const controller = this.application.getControllerForElementAndIdentifier(dialog, "panels-ui--sheet")
    controller?.close()
  }

  focusErrors() {
    const summary = this.element.querySelector("[data-rate-plan-editor-error-summary]")
    if (summary) requestAnimationFrame(() => summary.focus())
  }

  restoreRoomSelect() {
    if (!this.roomSelect || this.roomSelect.value === this.roomSelectValue) return

    this.roomSelect.value = this.roomSelectValue
    syncSelectMenu(this.application, this.roomSelect)
  }
}
