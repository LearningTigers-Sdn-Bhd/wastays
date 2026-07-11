import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--breadcrumb
//
// Tab integration outlet API only. Sibling-menu dropdowns are delegated to the
// canonical panels-ui--dropdown-menu controller (see PanelsUI::Breadcrumb template),
// so this controller carries no positioning/dismissal code of its own.
//
// `setTabLabel` / `setSubtabLabel` / `setSubtabSegmentVisible` are called by
// panels-ui--tabs via a Stimulus outlet when the active tab changes — replacing the
// old global `document.querySelector(...)` reach. Each no-ops when its target is
// absent, so tabs and breadcrumb stay decoupled.
export default class extends Controller {
  static targets = ["tabLabel", "subtabLabel", "subtabSegment"]

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
