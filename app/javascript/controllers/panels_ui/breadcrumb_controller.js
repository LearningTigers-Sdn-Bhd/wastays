import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tabLabel", "subtabLabel", "subtabSegment"]
  static values = {
    tabId: { type: String, default: "" },
    subtabIds: { type: Array, default: [] }
  }

  tabsChanged(event) {
    const { id, label, trigger, panel } = event.detail

    if (id === this.tabIdValue) {
      this.setTabLabel(label)
      this.syncNestedTab(panel)
      return
    }

    if (!this.subtabIdsValue.includes(id)) return

    const parentPanel = trigger?.closest('[data-slot="tabs-panel"]')
    if (parentPanel?.hidden) return

    this.setSubtabLabel(label)
    this.setSubtabSegmentVisible(true)
  }

  syncNestedTab(panel) {
    const activeTrigger = panel?.querySelector(
      '[data-slot="tabs-root"] [data-slot="tabs-trigger"][aria-selected="true"]'
    )
    const nestedId = activeTrigger?.closest('[data-slot="tabs-root"]')?.id

    if (!nestedId || !this.subtabIdsValue.includes(nestedId)) {
      this.setSubtabSegmentVisible(false)
      return
    }

    this.setSubtabLabel(activeTrigger.dataset.tabLabel)
    this.setSubtabSegmentVisible(true)
  }

  setTabLabel(label) {
    if (this.hasTabLabelTarget && label) this.tabLabelTarget.textContent = label
  }

  setSubtabLabel(label) {
    if (this.hasSubtabLabelTarget && label) this.subtabLabelTarget.textContent = label
  }

  setSubtabSegmentVisible(visible) {
    if (this.hasSubtabSegmentTarget) this.subtabSegmentTarget.classList.toggle("hidden", !visible)
  }
}
