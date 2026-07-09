import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "codeCheckbox", "selectAll", "hint", "bookingHeader", "bookingLabel", "bookingIcon", "bookingReason",
    "row", "summary", "submit"
  ]

  connect() {
    // Server-rendered booking headers already reflect real readiness (party/folio
    // existence). Don't recompute on load — with no codes selected yet, every row is
    // hidden, so a naive "any incomplete visible row" scan would find nothing wrong
    // and incorrectly flip every booking to ready. Only recompute once the user
    // actually selects codes or edits a row.
    this.applyCodeFilter()
    this.recomputeSummary()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.codeCheckboxTargets.forEach((checkbox) => { checkbox.checked = checked })
    this.applyCodeFilter()
    this.recomputeAllReadiness()
    this.recomputeSummary()
  }

  codeToggled() {
    this.applyCodeFilter()
    this.recomputeAllReadiness()
    this.recomputeSummary()
  }

  rowChanged(event) {
    const bookingId = event.target.closest("tr")?.dataset.bookingId
    if (bookingId) this.updateBookingReadiness(bookingId)
    this.recomputeSummary()
  }

  applyCodeFilter() {
    const selected = new Set(
      this.codeCheckboxTargets.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.dataset.codeId)
    )
    this.rowTargets.forEach((row) => {
      row.style.display = selected.has(row.dataset.codeId) ? "" : "none"
    })
  }

  recomputeAllReadiness() {
    const bookingIds = new Set(this.bookingHeaderTargets.map((header) => header.dataset.bookingId))
    bookingIds.forEach((bookingId) => this.updateBookingReadiness(bookingId))
  }

  // Only rows for currently-selected (visible) codes count toward readiness — an
  // unselected code's blank defaults shouldn't block apply for codes the user isn't touching.
  updateBookingReadiness(bookingId) {
    const header = this.bookingHeaderTargets.find((candidate) => candidate.dataset.bookingId === bookingId)
    const label = this.bookingLabelTargets.find((candidate) => candidate.closest("tr")?.dataset.bookingId === bookingId)
    const icon = this.bookingIconTargets.find((candidate) => candidate.closest("tr")?.dataset.bookingId === bookingId)
    const reason = this.bookingReasonTargets.find((candidate) => candidate.closest("tr")?.dataset.bookingId === bookingId)
    if (!header) return

    const incomplete = this.rowTargets.some((row) => {
      if (row.dataset.bookingId !== bookingId || row.dataset.routeLevel !== "parent") return false
      if (row.style.display === "none") return false

      const party = row.querySelector("select[data-billing-routes-target='party']")
      const folio = row.querySelector("select[data-billing-routes-target='folio']")
      return (party && party.value === "") || (folio && folio.value === "")
    })

    header.dataset.ready = incomplete ? "false" : "true"
    if (icon) icon.textContent = incomplete ? "⚠" : "✓"
    if (label) {
      label.classList.toggle("text-amber-700", incomplete)
      label.classList.toggle("text-slate-900", !incomplete)
    }
    if (reason) reason.textContent = incomplete ? "— Select a billing party and folio" : ""
  }

  recomputeSummary() {
    const codesSelected = this.codeCheckboxTargets.filter((checkbox) => checkbox.checked).length
    const needsReview = this.bookingHeaderTargets.filter((header) => header.dataset.ready === "false").length
    const total = this.bookingHeaderTargets.length

    this.summaryTarget.textContent =
      `${codesSelected} code${codesSelected === 1 ? "" : "s"} selected · ${total} booking${total === 1 ? "" : "s"} in group · ${needsReview} needs review`
    this.submitTarget.disabled = codesSelected === 0 || needsReview > 0
  }
}
