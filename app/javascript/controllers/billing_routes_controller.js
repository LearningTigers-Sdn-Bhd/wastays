import { Controller } from "@hotwired/stimulus"
import { selectMenuFor, syncSelectMenu } from "controllers/panels_ui/select_menu_sync"

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
    const party = this.nativeSelect(row, "party")
    const folio = this.nativeSelect(row, "folio")
    if (!party || !folio) return

    this.replaceFolioOptions(row, folio, party.value, reset)
  }

  updateChildRoute(row, reset = false) {
    const choice = this.nativeSelect(row, "childChoice")
    const folio = this.nativeSelect(row, "folio")
    const parent = row.closest("tr[data-child-of]")?.previousElementSibling ||
      this.rowTargets.find((candidate) => candidate.dataset.routeLevel === "parent" && candidate.dataset.codeId === row.dataset.parentCodeId)
    const parentParty = this.nativeSelect(parent, "party")
    const selectedPartyId = choice?.value.replace("party:", "")

    if (!choice || !folio) return
    if (choice.value === "guest_primary_folio") {
      this.setSelectValue(folio, row.dataset.primaryFolioId || "")
      this.setSelectDisabled(folio, true)
      return
    }

    if (choice.value === "inherit" || selectedPartyId === parentParty?.value) {
      this.setSelectValue(choice, "inherit")
      const parentFolio = this.nativeSelect(parent, "folio")
      if (parentFolio) this.setSelectValue(folio, parentFolio.value)
      this.setSelectDisabled(folio, true)
      return
    }

    this.replaceFolioOptions(row, folio, selectedPartyId, reset)
    this.setSelectDisabled(folio, false)
  }

  resetChildren(parentRow) {
    const codeId = parentRow?.dataset.codeId
    this.rowTargets.filter((row) => row.dataset.parentCodeId === codeId).forEach((row) => {
      const choice = this.nativeSelect(row, "childChoice")
      if (choice) this.setSelectValue(choice, "inherit")
      this.updateChildRoute(row)
    })
  }

  replaceFolioOptions(row, select, partyId, reset) {
    const choices = this.folioChoices(row).filter((choice) => choice.party_id === String(partyId))
    const renderedChoices = choices.length ? choices : [{ label: "No open folio available", value: "", disabled: true }]
    const currentAvailable = choices.some((choice) => String(choice.value) === select.value && !choice.disabled)
    const selectedValue = !reset && currentAvailable ? select.value : choices.find((choice) => !choice.disabled)?.value || ""
    const controller = selectMenuFor(this.application, select)

    if (controller) {
      controller.replaceOptions(renderedChoices, selectedValue)
    } else {
      select.replaceChildren(...renderedChoices.map((choice) => {
        const option = document.createElement("option")
        option.value = choice.value
        option.textContent = choice.label
        option.disabled = Boolean(choice.disabled)
        return option
      }))
      select.value = String(selectedValue)
    }
  }

  folioChoices(row) {
    try {
      return JSON.parse(row.dataset.folioOptions || "[]")
    } catch (_error) {
      return []
    }
  }

  nativeSelect(row, targetName) {
    const target = row?.querySelector(`[data-billing-routes-target~='${targetName}']`)
    if (!target) return null

    return target.matches("select") ? target : target.querySelector("select")
  }

  setSelectValue(select, value) {
    select.value = String(value || "")
    syncSelectMenu(this.application, select)
  }

  setSelectDisabled(select, disabled) {
    select.disabled = disabled
    const controller = selectMenuFor(this.application, select)
    if (!controller) return

    controller.triggerTarget.disabled = disabled
    controller.element.dataset.disabled = disabled.toString()
  }

  toggle(event) {
    const parent = event.currentTarget.closest("tr")
    const children = parent.nextElementSibling
    const expanded = !children.classList.toggle("hidden")
    event.currentTarget.setAttribute("aria-expanded", expanded)
    event.currentTarget.querySelector("svg")?.classList.toggle("rotate-90", expanded)
  }
}
