import { Controller } from "@hotwired/stimulus"

// Syncs filter form parameter values to export link hrefs (PDF/Excel)
// so that exports always reflect the currently applied filters.
//
// Attach to the filter form element. Export links are located by their
// element IDs (configurable via data-export-sync-pdf-id-value, etc.).
export default class extends Controller {
  static values = {
    pdfId:   { type: String, default: "export-pdf-link" },
    excelId: { type: String, default: "export-excel-link" }
  }

  connect() {
    this.sync()
  }

  sync() {
    const params = {
      q:           this.#fieldValue("q"),
      assigned_to: this.#fieldValue("assigned_to"),
      room_status: this.#fieldValue("room_status"),
      date:        this.#fieldValue("date")
    }

    this.#updateLink(this.pdfIdValue, params)
    this.#updateLink(this.excelIdValue, params)
  }

  // -- Private --

  #fieldValue(name) {
    return this.element.querySelector(`[name="${name}"]`)?.value ?? ""
  }

  #updateLink(linkId, params) {
    const link = document.getElementById(linkId)
    if (!link) return

    const url = new URL(link.href, window.location.origin)
    Object.entries(params).forEach(([key, value]) => url.searchParams.set(key, value))
    link.href = url.pathname + url.search
  }
}
