import { Controller } from "@hotwired/stimulus"

// Add and remove rows in an editable record table.
//
// The blank row lives in a <template> that sits after the last record, so it
// doubles as the insertion anchor — new rows go in immediately before it and
// land at the end of the list without the table body needing a target of its
// own. Its index placeholder is swapped for a fresh one on each add so the
// server sees a distinct set of params per row.
export default class extends Controller {
  static targets = ["template", "row", "empty", "footer"]

  add(event) {
    // A grouped table carries one template per group, so the add button names
    // the run it extends. Ungrouped tables have exactly one and say nothing.
    const group = event?.params?.group
    const template = group
      ? this.templateTargets.find(candidate => candidate.dataset.recordTableGroup === group)
      : this.templateTargets[0]
    if (!template) return

    const index = `${Date.now()}-${this.rowTargets.length}`
    template.insertAdjacentHTML("beforebegin", template.innerHTML.replaceAll("NEW_RECORD", index))
    this.#syncEmptyState()
    this.dispatch("changed")

    // Focus the first field, not the row's remove button — that sits ahead of
    // the fields in the markup and would hand focus straight to a destructive
    // control the operator never asked for.
    const row = template.previousElementSibling
    row?.querySelector("input:not([type='hidden']), select, textarea")?.focus()
  }

  async remove(event) {
    const row = event.currentTarget.closest(
      "[data-record-table-target='row'], [data-record-table-target='group']"
    )
    if (!row) return

    // Removing a group takes the records priced under it with it — they have no
    // meaning once their heading is gone.
    if (row.dataset.recordTableTarget === "group") return this.#removeGroup(row, event)

    // A saved record has to report its own removal, so it stays in the DOM
    // marked for destruction. A soft row does the same for a different reason:
    // it is the only copy of a record the operator may want back.
    if (row.dataset.recordTablePersisted === "true" || row.dataset.recordTableSoft === "true") {
      const message = event.currentTarget.dataset.recordTableConfirm
      const confirmed = !message || await Turbo.config.forms.confirm(message, event.currentTarget)
      if (!confirmed) return

      const destroyInput = row.querySelector("input[data-record-table-destroy]")
      if (destroyInput) destroyInput.value = "1"
      row.hidden = true
    } else {
      row.remove()
    }

    this.#syncEmptyState()
    this.dispatch("changed")
  }

  // A group owns every sibling up to the next heading: its records and its own
  // clone template.
  #groupMembers(group) {
    const members = []
    const boundaries = ["group", "empty"]
    let node = group.nextElementSibling
    while (node && !boundaries.includes(node.dataset.recordTableTarget)) {
      members.push(node)
      node = node.nextElementSibling
    }
    return members
  }

  async #removeGroup(group, event) {
    const members = this.#groupMembers(group)

    if (group.dataset.recordTablePersisted === "true") {
      const message = event.currentTarget.dataset.recordTableConfirm
      const confirmed = !message || await Turbo.config.forms.confirm(message, event.currentTarget)
      if (!confirmed) return

      const destroyInput = group.querySelector("input[data-record-table-destroy]")
      if (destroyInput) destroyInput.value = "1"
      group.hidden = true
      members.forEach(member => { member.hidden = true })
    } else {
      members.forEach(member => member.remove())
      group.remove()
    }

    this.#syncEmptyState()
    this.dispatch("changed")
  }

  // The empty state carries its own add button, so the footer's would be the
  // same offer twice. Exactly one of the two is on screen at any moment.
  #syncEmptyState() {
    const populated = this.rowTargets.some(row => !row.hidden)
    if (this.hasEmptyTarget) this.emptyTarget.hidden = populated
    if (this.hasFooterTarget) this.footerTarget.hidden = !populated
  }
}
