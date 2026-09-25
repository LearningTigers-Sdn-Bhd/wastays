import { Controller } from "@hotwired/stimulus"

// Shows a panel only while a select holds one of the values it lists, or while
// a checkbox source is checked:
//   <div data-controller="value-reveal">
//     <select data-value-reveal-target="source" data-action="value-reveal#update">…</select>
//     <div data-value-reveal-target="panel" data-reveal-values="except only">…</div>
//   <div data-controller="value-reveal">
//     <input type="checkbox" data-value-reveal-target="source" data-action="change->value-reveal#update">
//     <div data-value-reveal-target="panel" data-reveal-values="checked">…</div>
// A hidden panel's fields are disabled so they do not submit stale choices.
export default class extends Controller {
  static targets = ["source", "panel"]

  connect() {
    this.update()
  }

  update() {
    const value = this.valueOf(this.sourceTarget)

    this.panelTargets.forEach((panel) => {
      const shown = (panel.dataset.revealValues || "").split(/\s+/).includes(value)
      panel.hidden = !shown
      panel.querySelectorAll("input, select, textarea").forEach((control) => { control.disabled = !shown })
    })
  }

  // The source may be a checkbox (its "value" is whether it's checked), a bare
  // <select>, or a PanelsUI::SelectMenu wrapper div (which does not itself
  // carry a `.value`) around the real native <select>.
  valueOf(target) {
    if (target.matches("input[type='checkbox']")) return target.checked ? "checked" : "unchecked"
    return (target.matches("select") ? target : target.querySelector("select"))?.value
  }
}
