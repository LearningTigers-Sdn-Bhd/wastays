import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["ratePlanId"]

  clearRatePlanSelection(event) {
    if (event.target.name !== "rate_plan_attachment[rate_plan_name]") return

    this.ratePlanIdTarget.value = ""
  }

  selectRatePlan(event) {
    const result = event.detail?.result
    this.ratePlanIdTarget.value = result?.value || result?.id || ""
  }
}
