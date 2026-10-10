import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["destination", "source", "entry", "group", "summary"]

  connect() { this.destinationChanged() }

  destinationChanged() {
    if (!this.hasDestinationTarget) return
    const destinationId = this.destinationTarget.querySelector("select").value
    this.groupTargets.forEach(group => {
      const isTarget = group.dataset.folioId === destinationId
      group.querySelector("[data-folio-transfer-source-content]").hidden = isTarget
      group.querySelector("[data-folio-transfer-receiving]").hidden = !isTarget
      group.querySelector("[data-folio-transfer-receiving-message]").hidden = !isTarget
      group.querySelector("[data-folio-transfer-selection-count]").hidden = isTarget
      group.querySelectorAll('[data-folio-transfer-target="entry"]').forEach(entry => {
        entry.disabled = isTarget || entry.dataset.eligible !== "true"
        entry.closest(".panel-checkbox").dataset.disabled = String(entry.disabled)
        if (isTarget) entry.checked = false
      })
    })
    this.refreshSelection()
  }

  entryChanged() {
    this.refreshSelection()
  }

  selectCharges() {
    this.groupTargets.forEach(group => {
      group.querySelectorAll('[data-folio-transfer-target="entry"]').forEach(entry => {
        if (!entry.disabled && entry.dataset.charge === "true") {
          entry.checked = true
        }
      })
    })
    this.refreshSelection()
  }

  clear() {
    this.entryTargets.forEach(entry => { entry.checked = false })
    this.refreshSelection()
  }

  refreshSelection() {
    let folios = 0
    this.groupTargets.forEach(group => {
      const count = group.querySelectorAll('[data-folio-transfer-target="entry"]:checked:not(:disabled)').length
      group.querySelector('[data-folio-transfer-target="source"]').disabled = count === 0
      group.querySelector("[data-folio-transfer-selection-count]").textContent = `${count} selected`
      if (count > 0) folios += 1
    })
    if (!this.hasSummaryTarget) return
    const selected = this.entryTargets.filter(entry => entry.checked && !entry.disabled)
    if (selected.length === 0) {
      this.summaryTarget.textContent = "No entries selected. Choose charges or payment credits above."
      return
    }
    const charges = selected.filter(entry => entry.dataset.charge === "true").length
    const payments = selected.length - charges
    const parts = []
    if (charges > 0) parts.push(`${charges} ${charges === 1 ? "charge" : "charges"}`)
    if (payments > 0) parts.push(`${payments} payment ${payments === 1 ? "credit" : "credits"}`)
    this.summaryTarget.textContent = `${parts.join(" and ")} selected from ${folios} ${folios === 1 ? "folio" : "folios"}.`
  }
}
