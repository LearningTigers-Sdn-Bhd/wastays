import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scope", "checkbox", "panel", "row"]
  static values = {
    masterDetail: { type: Boolean, default: false },
    initialBookingId: String,
    selectionMode: { type: String, default: "checkbox" }
  }

  connect() {
    this.activeBookingId = this.initialBookingIdValue || this.selectedBookingIds[0] || null
    if (this.radioMode) this.ensureRadioSelection()
    this.reconcile()
  }

  scopeChanged() {
    if (this.selectedScope === "group") {
      this.eligibleCheckboxes.forEach((checkbox) => { checkbox.checked = true })
    } else if (this.masterDetailValue) {
      this.eligibleCheckboxes.forEach((checkbox) => {
        checkbox.checked = checkbox.dataset.bookingId === this.activeBookingId
      })
    } else {
      this.eligibleCheckboxes.forEach((checkbox) => { checkbox.checked = false })
    }

    this.reconcile()
  }

  selectionChanged(event) {
    if (event.currentTarget.checked || this.radioMode) this.activeBookingId = event.currentTarget.dataset.bookingId
    if (this.radioMode) this.ensureRadioSelection()
    this.syncScope()
    this.reconcile()
  }

  activatePanel(event) {
    this.activeBookingId = event.currentTarget.dataset.bookingId
    const checkbox = this.checkboxFor(this.activeBookingId)
    if (checkbox && !checkbox.disabled) checkbox.checked = true
    if (this.radioMode) this.ensureRadioSelection()
    this.syncScope()
    this.reconcile()
  }

  configurationChanged() {
    this.reconcile()
  }

  reconcile() {
    if (this.masterDetailValue) {
      if (this.radioMode) this.ensureRadioSelection()
      if (!this.selectedBookingIds.includes(this.activeBookingId)) {
        this.activeBookingId = this.selectedBookingIds[0] || null
      }
      this.syncPanels()
      this.syncRows()
    }
    this.syncSubmit()
  }

  syncPanels() {
    this.panelTargets.forEach((panel) => {
      const selected = this.selectedBookingIds.includes(panel.dataset.bookingId)
      const active = selected && panel.dataset.bookingId === this.activeBookingId
      panel.hidden = !active
      panel.setAttribute("aria-hidden", String(!active))
      panel.querySelectorAll("input, select, textarea").forEach((field) => { field.disabled = !selected })
    })
  }

  syncRows() {
    this.rowTargets.forEach((row) => {
      const active = row.dataset.bookingId === this.activeBookingId
      row.setAttribute("aria-selected", String(active))
      row.classList.toggle("font-semibold", active)
      row.classList.toggle("text-slate-950", active)
    })
  }

  syncSubmit() {
    const submit = this.element.querySelector("input[type='submit'], button[type='submit']")
    if (!submit) return

    const complete = !this.masterDetailValue || this.selectedBookingIds.every((id) => this.panelComplete(id))
    const enabled = this.selectedBookingIds.length > 0 && complete
    submit.disabled = !enabled
    submit.classList.toggle("opacity-50", !enabled)
    submit.classList.toggle("cursor-not-allowed", !enabled)
  }

  syncScope() {
    if (this.radioMode) return

    const allSelected = this.eligibleCheckboxes.length > 0 && this.eligibleCheckboxes.every((checkbox) => checkbox.checked)
    const groupScope = this.scopeTargets.find((input) => input.value === "group")
    const individualScope = this.scopeTargets.find((input) => input.value === "individual")
    if (groupScope) groupScope.checked = allSelected
    if (individualScope) individualScope.checked = !allSelected
  }

  panelComplete(bookingId) {
    const panel = this.panelTargets.find((candidate) => candidate.dataset.bookingId === bookingId)
    if (!panel) return false
    const requiredFields = Array.from(panel.querySelectorAll("[data-reinstatement-required='true']"))
    return requiredFields.length > 0 && requiredFields.every((field) => field.value.trim() !== "")
  }

  checkboxFor(bookingId) {
    return this.checkboxTargets.find((checkbox) => checkbox.dataset.bookingId === bookingId)
  }

  get eligibleCheckboxes() {
    return this.checkboxTargets.filter((checkbox) => !checkbox.disabled)
  }

  get selectedBookingIds() {
    return this.eligibleCheckboxes.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.dataset.bookingId)
  }

  get selectedScope() {
    return this.scopeTargets.find((input) => input.checked)?.value || "individual"
  }

  ensureRadioSelection() {
    if (!this.radioMode || this.eligibleCheckboxes.length === 0) return

    const selected = this.eligibleCheckboxes.find((input) => input.checked)
    if (selected) {
      this.activeBookingId = selected.dataset.bookingId
      return
    }

    const preferred = this.checkboxFor(this.activeBookingId) || this.eligibleCheckboxes[0]
    preferred.checked = true
    this.activeBookingId = preferred.dataset.bookingId
  }

  get radioMode() {
    return this.selectionModeValue === "radio"
  }
}
