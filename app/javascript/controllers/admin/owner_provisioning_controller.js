import { Controller } from "@hotwired/stimulus"

// Swaps the create-hotel footer between the two provisioning paths. With the
// switch off the superadmin chooses whether to send the activation email; with
// it on there is no invitation at all, so a single action is the honest choice.
export default class extends Controller {
  static targets = ["switch", "inviteActions", "verifiedActions"]

  connect() {
    this.refresh()
  }

  refresh() {
    const verified = this.hasSwitchTarget && this.switchTarget.checked

    // display is set inline rather than via a `hidden` class because both
    // wrappers need `display: contents` when shown, and Tailwind's display
    // utilities would collide unpredictably with each other.
    this.inviteActionsTarget.style.display = verified ? "none" : "contents"
    this.verifiedActionsTarget.style.display = verified ? "contents" : "none"
  }
}
