import { Controller } from "@hotwired/stimulus"

// Hides rows flagged data-archived until the toggle is switched on, and only
// offers the toggle while at least one such row exists. Rows are swapped by
// Turbo Streams when a plan is archived or restored, so visibility is
// recomputed whenever the list changes rather than set once on connect.
//   <section data-controller="archived-toggle">
//     <span data-archived-toggle-target="count"></span>
//     <div data-archived-toggle-target="control" hidden>
//       <input type="checkbox" data-action="change->archived-toggle#update" data-archived-toggle-target="source">
//     </div>
//     <div data-archived-toggle-target="list"><div data-archived>…</div></div>
export default class extends Controller {
  static targets = ["list", "control", "source", "count"]

  connect() {
    this.observer = new MutationObserver(() => this.update())
    this.observer.observe(this.listTarget, { childList: true, subtree: true })
    this.update()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  update() {
    const archived = this.listTarget.querySelectorAll("[data-archived]")
    const shown = this.hasSourceTarget && this.sourceTarget.checked

    this.controlTarget.hidden = archived.length === 0
    if (archived.length === 0 && this.hasSourceTarget) this.sourceTarget.checked = false

    archived.forEach((row) => { row.hidden = !shown })
    if (this.hasCountTarget) {
      const total = this.listTarget.querySelectorAll("[role='listitem']").length
      this.countTarget.textContent = shown ? total : total - archived.length
    }
  }
}
