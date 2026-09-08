import { Controller } from "@hotwired/stimulus"

// A 24-hour desk keeps no clock, so the two time fields go away while the
// switch is on. Hidden rather than removed: turning the switch back off must
// bring the same fields back with whatever was typed in them.
export default class extends Controller {
  static targets = ["switch", "hours"]

  connect() {
    this.sync()
  }

  sync() {
    this.hoursTarget.hidden = this.switchTarget.checked
  }
}
