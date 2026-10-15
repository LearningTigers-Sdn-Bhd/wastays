import { Controller } from "@hotwired/stimulus"

// Room-charge correction sheet. The "Set all nights" field copies its value
// into every per-night input. Pure UI: the server reads only the per-night
// fields and ignores nights whose amount did not change.
export default class extends Controller {
  static targets = ["all", "night"]

  fill() {
    const value = this.allTarget.value
    if (value === "") return
    this.nightTargets.forEach((input) => { input.value = value })
  }
}
