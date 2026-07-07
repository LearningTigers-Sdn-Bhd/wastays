import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["row", "children", "chevron", "party", "folio", "childChoice"]

  connect() {
    this.rowTargets.forEach((row) => {
      if (row.dataset.routeLevel === "child") this.updateChildRoute(row)
      else this.filterFolios(row)
    })
  }

  partyChanged(event) {
    const row = event.target.closest("tr")
    this.filterFolios(row, true)
    if (row.dataset.routeLevel === "parent") this.resetChildren(row)
  }

  parentFolioChanged(event) {
    this.resetChildren(event.target.closest("tr"))
  }

  childChoiceChanged(event) {
    this.updateChildRoute(event.target.closest("tr"), true)
  }

  filterFolios(row, reset = false) {
    const party = row.querySelector("select[data-billing-routes-target='party']")
    const folio = row.querySelector("select[data-billing-routes-target='folio']")
    if (!party || !folio) return
    Array.from(folio.options).forEach((option) => {
      const matches = (option.dataset.partyId || "") === party.value
      option.hidden = !matches
      option.disabled = !matches || option.dataset.closed === "true"
    })
    if (reset || folio.selectedOptions[0]?.hidden) {
      const available = Array.from(folio.options).find((option) => !option.hidden && !option.disabled)
      folio.value = available?.value || ""
    }
  }

  updateChildRoute(row, reset = false) {
    const choice = row.querySelector("select[data-billing-routes-target='childChoice']")
    const folio = row.querySelector("select[data-billing-routes-target='folio']")
    const parent = row.closest("tr[data-child-of]")?.previousElementSibling ||
      this.rowTargets.find((candidate) => candidate.dataset.routeLevel === "parent" && candidate.dataset.codeId === row.dataset.parentCodeId)
    const parentParty = parent?.querySelector("select[data-billing-routes-target='party']")
    const selectedPartyId = choice?.value.replace("party:", "")

    if (!choice || !folio) return
    if (choice.value === "guest_primary_folio") {
      folio.disabled = true
      folio.value = row.dataset.primaryFolioId || ""
      return
    }

    if (choice.value === "inherit" || selectedPartyId === parentParty?.value) {
      choice.value = "inherit"
      folio.disabled = true
      const parentFolio = parent?.querySelector("select[data-billing-routes-target='folio']")
      if (parentFolio) folio.value = parentFolio.value
      return
    }

    folio.disabled = false
    Array.from(folio.options).forEach((option) => {
      const matches = (option.dataset.partyId || "") === selectedPartyId
      option.hidden = !matches
      option.disabled = !matches || option.dataset.closed === "true"
    })
    if (reset || folio.selectedOptions[0]?.hidden) {
      const available = Array.from(folio.options).find((option) => !option.hidden && !option.disabled)
      folio.value = available?.value || ""
    }
  }

  resetChildren(parentRow) {
    const codeId = parentRow?.dataset.codeId
    this.rowTargets.filter((row) => row.dataset.parentCodeId === codeId).forEach((row) => {
      const choice = row.querySelector("select[data-billing-routes-target='childChoice']")
      if (choice) choice.value = "inherit"
      this.updateChildRoute(row)
    })
  }

  toggle(event) {
    const parent = event.currentTarget.closest("tr")
    const children = parent.nextElementSibling
    const expanded = !children.classList.toggle("hidden")
    event.currentTarget.setAttribute("aria-expanded", expanded)
    event.currentTarget.querySelector("svg")?.classList.toggle("rotate-90", expanded)
  }
}
