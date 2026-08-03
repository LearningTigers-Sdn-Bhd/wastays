import { Controller } from "@hotwired/stimulus"

// Syncs the filter form's values into the export links, so an export always
// carries the filters the user is actually looking at.
//
// Attach to the filter form. Every element the form itself would submit is
// copied over, so a new filter needs no change here. The links to update are
// named by data-export-sync-link-ids-value, defaulting to the standard three.
export default class extends Controller {
  static values = {
    linkIds: { type: Array, default: ["export-pdf-link", "export-excel-link", "export-csv-link"] }
  }

  connect() {
    this.sync()
  }

  sync() {
    const params = this.#formParams()
    this.linkIdsValue.forEach(linkId => this.#updateLink(linkId, params))
  }

  // -- Private --

  // The form's own named fields, which is exactly what submitting it would send.
  #formParams() {
    return Array.from(new FormData(this.element).entries())
  }

  #updateLink(linkId, params) {
    const link = document.getElementById(linkId)
    if (!link) return

    const url = new URL(link.href, window.location.origin)
    params.forEach(([key, value]) => url.searchParams.set(key, value))
    link.href = url.pathname + url.search
  }
}
