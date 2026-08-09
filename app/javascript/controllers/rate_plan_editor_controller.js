import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static targets = ["form", "saveButton", "saveLabel"]
  static values = { editUrl: String, roomTypeId: Number }

  connect() {
    this.pristine = new Map(this.formTargets.map((form) => [form, this.serialize(form)]))
    this.pending = null
    this.submitting = false
    this.boundDocumentClick = this.documentClick.bind(this)
    this.boundTabChange = this.tabChanged.bind(this)
    this.boundSubmit = () => { this.submitting = true }
    this.roomSelect = this.element.querySelector('[name="rate_plan_room_selector[room_type_id]"]')
    this.roomSelectValue = this.roomSelect?.value
    document.addEventListener("click", this.boundDocumentClick, true)
    window.addEventListener("panels-ui--tabs:change", this.boundTabChange)
    this.element.addEventListener("submit", this.boundSubmit, true)
    this.updateFooter()
    this.focusErrors()
  }

  disconnect() {
    document.removeEventListener("click", this.boundDocumentClick, true)
    window.removeEventListener("panels-ui--tabs:change", this.boundTabChange)
    this.element.removeEventListener("submit", this.boundSubmit, true)
  }

  documentClick(event) {
    if (this.submitting || !this.currentFormDirty) return

    const tab = event.target.closest("[data-rate-plan-editor-destination]")
    if (tab && tab.getAttribute("aria-selected") !== "true") {
      event.preventDefault()
      event.stopImmediatePropagation()
      const url = new URL(this.editUrlValue, window.location.origin)
      url.searchParams.set("tab", tab.dataset.ratePlanEditorDestination)
      if (this.hasRoomTypeIdValue) url.searchParams.set("room_type_id", this.roomTypeIdValue)
      this.confirmDiscard({ type: "visit", url: url.pathname + url.search })
      return
    }

    const guarded = event.target.closest("[data-rate-plan-editor-room-url], [data-rate-plan-editor-guard]")
    if (!guarded) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.confirmDiscard({ type: "click", element: guarded })
  }

  tabChanged(event) {
    if (event.detail?.id !== "rate-plan-editor-tabs") return
    this.updateFooter()
  }

  selectRoom(event) {
    const select = event.target.closest("select")
    const url = select?.value
    if (!url) return

    if (this.currentFormDirty) {
      this.restoreRoomSelect()
      this.confirmDiscard({ type: "visit", url })
    } else {
      Turbo.visit(url, { frame: "settings_action_sheet" })
    }
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

  updateFooter() {
    if (!this.hasSaveButtonTarget || !this.hasSaveLabelTarget) return

    const panel = this.element.querySelector('[role="tabpanel"]:not([hidden])')
    const form = panel?.querySelector("form[data-rate-plan-editor-target~='form']")
    const section = form?.dataset.editorSection
    const labels = {
      details: "Save plan details",
      rooms: "Save room pricing",
      children: "Save child pricing"
    }

    this.saveButtonTarget.hidden = !form
    if (!form) {
      this.saveButtonTarget.removeAttribute("form")
      return
    }

    this.saveButtonTarget.setAttribute("form", form.id)
    this.saveLabelTarget.textContent = labels[section] || "Save changes"
  }

  get currentForm() {
    const panel = this.element.querySelector('[role="tabpanel"]:not([hidden])')
    return panel?.querySelector("form[data-rate-plan-editor-target~='form']") || null
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
    const dialog = this.element.querySelector("#edit-rate-plan-sheet")
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
    const root = this.roomSelect.closest("[data-controller~='panels-ui--select-menu']")
    const controller = root && this.application.getControllerForElementAndIdentifier(root, "panels-ui--select-menu")
    controller?.syncFromNative()
  }
}
