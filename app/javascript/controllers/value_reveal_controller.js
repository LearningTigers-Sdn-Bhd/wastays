import { Controller } from "@hotwired/stimulus"

// Shows a panel only while a select holds one of the values it lists:
//   <div data-controller="value-reveal">
//     <select data-value-reveal-target="source" data-action="value-reveal#update">…</select>
//     <div data-value-reveal-target="panel" data-reveal-values="except only">…</div>
// A hidden panel's fields are disabled so they do not submit stale choices.
export default class extends Controller {
  static targets = ["source", "panel"]

  connect() {
    this.update()
  }

  update() {
    const value = this.sourceTarget.value

    this.panelTargets.forEach((panel) => {
      const shown = (panel.dataset.revealValues || "").split(/\s+/).includes(value)
      panel.hidden = !shown
      panel.querySelectorAll("input, select, textarea").forEach((control) => { control.disabled = !shown })
    })
  }
}
