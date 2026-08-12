import { Controller } from "@hotwired/stimulus"

// Adds a rate plan to the grouped pricing table. Room attachment is not a client
// concern any more — a plan covers every room category, so the rows come with it
// and there are no sibling choices to keep in step.
export default class extends Controller {
  static targets = ["plan", "endDate"]
  static values = { readOnly: Boolean }

  connect() {
    // The clone source is a real group in the table. Lift it out of the DOM so
    // its blank fields never submit, keeping its rows as the template.
    const template = this.planTargets.find(plan => plan.dataset.newPlanTemplate === "true")
    const heading = template?.closest("[data-record-table-target='group']")
    if (!heading) return

    const rows = this.#groupRows(heading)
    this.planTemplate = [heading, ...rows].map(node => node.outerHTML).join("")
    rows.forEach(node => node.remove())
    heading.remove()
  }

  addPlan() {
    if (!this.planTemplate) return

    const body = this.element.querySelector(".panel-record-table--rates tbody")
    if (!body) return

    const key = `plan-new-${Date.now()}`
    const markup = this.planTemplate.replaceAll("PLAN_KEY", key)
    const anchor = body.querySelector("[data-record-table-target='empty']")

    if (anchor) anchor.insertAdjacentHTML("beforebegin", markup)
    else body.insertAdjacentHTML("beforeend", markup)

    const plan = this.planTargets.at(-1)
    plan?.removeAttribute("data-new-plan-template")
    plan?.querySelector("input[name$='[name]']")?.focus()
  }

  // Every sibling row up to the next heading belongs to this group.
  #groupRows(heading) {
    const boundaries = ["group", "empty"]
    const rows = []
    let node = heading.nextElementSibling
    while (node && !boundaries.includes(node.dataset.recordTableTarget)) {
      rows.push(node)
      node = node.nextElementSibling
    }
    return rows
  }
}
