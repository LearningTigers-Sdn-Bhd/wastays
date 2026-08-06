import { Controller } from "@hotwired/stimulus"

// On a group booking, the "Add folio window" sheet lets you pick which child
// booking the folio belongs to; the billing-party list has to follow.
//
// Both fields render as PanelsUI::SelectMenu, so the party options are swapped
// through the select-menu controller's own `replaceOptions` API rather than by
// rewriting <option> HTML underneath it.
export default class extends Controller {
  static targets = ["booking", "party", "partyData"]

  change() {
    const bookingId = this.selectFor(this.bookingTarget).value
    const source = this.partyDataTargets.find((item) => item.dataset.bookingId === bookingId)
    const choices = source ? JSON.parse(source.textContent) : []

    this.partySelectMenu?.replaceOptions(
      [{ label: "Select billing party", value: "" }].concat(
        choices.length ? choices : [{ label: "No billing party available", value: "", disabled: true }]
      )
    )
  }

  get partySelectMenu() {
    const root = this.partyTarget.querySelector("[data-controller~='panels-ui--select-menu']")
    if (!root) return null

    return this.application.getControllerForElementAndIdentifier(root, "panels-ui--select-menu")
  }

  selectFor(wrapper) {
    return wrapper.querySelector("select")
  }
}
