import { Controller } from "@hotwired/stimulus"

// Adds a rate plan to the grouped pricing table, and keeps each plan's room
// coverage in step with itself: a room taken off a plan stays in the table
// hidden, and "+ Room" adds a row that asks which category to put back.
export default class extends Controller {
  static targets = ["plan", "endDate"]
  static values = { readOnly: Boolean }

  connect() {
    // The clone source is a real group in the table. Lift it out of the DOM so
    // its blank fields never submit, keeping its rows as the template.
    const template = this.planTargets.find(plan => plan.dataset.newPlanTemplate === "true")
    const heading = template?.closest("[data-record-table-target='group']")
    if (heading) {
      const rows = this.#groupRows(heading)
      this.planTemplate = [heading, ...rows].map(node => node.outerHTML).join("")
      rows.forEach(node => node.remove())
      heading.remove()
    }

    this.#syncCoverage()
  }

  // Fired by the record table after any add or remove.
  changed() {
    this.#syncCoverage()
  }

  // The picker row is a question, not a record: answering it hands the plan back
  // the room's own row, which already carries that room's occupancy columns.
  chooseRoom(event) {
    const picker = event.target.closest("tr")
    const heading = this.#heading(picker)
    const row = this.#roomRow(heading, event.target.value)
    if (!row) return

    picker.remove()
    row.hidden = false
    const destroyInput = row.querySelector("input[data-record-table-destroy]")
    if (destroyInput) destroyInput.value = "0"

    this.#syncCoverage()
    row.querySelector("input:not([type='hidden']), select")?.focus()
  }

  // Each plan answers for its own coverage: a picker offers only the categories
  // that plan is not selling, and stops being offered at all once it sells them
  // every one. The last remaining room cannot be removed either — a plan that
  // prices nothing is one the save path rejects, and removing the plan itself is
  // the control one row up.
  #syncCoverage() {
    this.element.querySelectorAll("[data-record-table-target='group']").forEach(heading => {
      const rows = this.#groupRows(heading).filter(row => row.querySelector("input[data-record-table-destroy]"))
      if (rows.length === 0) return

      const remaining = rows.filter(row => !row.hidden)
      remaining.forEach(row => {
        const button = row.querySelector(".panel-record-table__control button")
        if (button) button.disabled = remaining.length === 1
      })

      const covered = remaining.map(row => row.dataset.recordTableKey?.replace("assignment-", ""))
      this.#groupRows(heading)
        .filter(row => row.querySelector("select[name$='[room_type_id]']"))
        .forEach(picker => covered.forEach(roomId => this.#dropChoice(picker, roomId)))

      const add = heading.querySelector("[data-record-table-group-param]")
      if (add) add.hidden = covered.length === rows.length
    })
  }

  // Both halves of the select menu go: the native <option> that submits and the
  // styled row that mirrors it. Leaving either behind offers a room the plan
  // already sells, which the save path counts as a duplicate.
  #dropChoice(picker, roomId) {
    picker.querySelector(`select option[value="${roomId}"]`)?.remove()
    picker.querySelector(`[role='option'][data-value="${roomId}"]`)?.remove()
  }

  #heading(row) {
    let node = row?.previousElementSibling
    while (node && node.dataset.recordTableTarget !== "group") node = node.previousElementSibling
    return node
  }

  #roomRow(heading, roomId) {
    if (!heading) return null

    return this.#groupRows(heading).find(row => row.dataset.recordTableKey === `assignment-${roomId}`)
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
    this.#syncCoverage()
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
