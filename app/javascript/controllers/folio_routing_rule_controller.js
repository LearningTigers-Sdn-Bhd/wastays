import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["chargeCode", "targetFolio", "taxGroup", "childFolio"]

  connect() {
    this.sync()
  }

  sync() {
    this.syncVisibleTaxGroup()
    this.syncBlankChildFolios()
  }

  markChildExplicit(event) {
    event.currentTarget.dataset.explicitValue = event.currentTarget.value
  }

  syncVisibleTaxGroup() {
    const selectedChargeCodeId = this.chargeCodeTarget.value

    this.taxGroupTargets.forEach((group) => {
      group.classList.toggle("hidden", group.dataset.chargeCodeId !== selectedChargeCodeId)
    })
  }

  syncBlankChildFolios() {
    const targetFolioId = this.targetFolioTarget.value

    this.visibleChildFolioTargets().forEach((select) => {
      if (select.dataset.explicitValue === undefined) {
        select.dataset.explicitValue = select.value
      }

      if (select.dataset.explicitValue === "") {
        select.value = targetFolioId
      }
    })
  }

  visibleChildFolioTargets() {
    return this.childFolioTargets.filter((select) => !select.closest(".hidden"))
  }
}
