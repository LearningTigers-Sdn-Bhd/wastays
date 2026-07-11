import { Controller } from "@hotwired/stimulus"

const expandedGroups = new Map()

export default class extends Controller {
  static targets = ["group"]
  static values = { scope: String }

  connect() {
    this.groupTargets.forEach((group) => {
      const remembered = expandedGroups.get(this.keyFor(group))
      if (remembered !== undefined) group.open = remembered
    })
  }

  remember(event) {
    expandedGroups.set(this.keyFor(event.currentTarget), event.currentTarget.open)
  }

  keyFor(group) {
    return `${this.scopeValue}:${group.dataset.groupKey}`
  }
}
