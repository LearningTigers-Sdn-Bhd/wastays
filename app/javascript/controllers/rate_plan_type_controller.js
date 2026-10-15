import { Controller } from "@hotwired/stimulus"

// The Room / Day use switch at the top of a rate plan. Day use reveals the
// hours field; switching back to Room clears it, because a plan with no hours
// is an overnight plan.
export default class extends Controller {
  static targets = ["hoursField", "hours"]

  select(event) {
    const dayUse = event.detail.value === "day_use"
    this.hoursFieldTarget.hidden = !dayUse
    this.hoursTarget.required = dayUse
    if (!dayUse) this.hoursTarget.value = ""
    else this.hoursTarget.focus()
  }
}
