import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["booking", "party", "template"]

  change() {
    const template = this.templateTargets.find((item) => item.dataset.bookingId === this.bookingTarget.value)
    this.partyTarget.innerHTML = template ? template.innerHTML : '<option value="">Select billing party</option>'
  }
}
