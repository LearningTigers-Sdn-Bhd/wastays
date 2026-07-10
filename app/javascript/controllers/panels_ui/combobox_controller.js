import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

export default class extends Controller {
  static targets = ["native"]
  static values = { placeholder: String, maxOptions: Number }

  connect() {
    this.onFormReset = this.onFormReset.bind(this)

    // Snapshot the native's classes before Tom Select copies them onto .ts-wrapper
    // during construction (it also mutates this classList, e.g. hidden-accessible —
    // so it must be read now). See the strip below.
    const copiedNativeClasses = this.nativeTarget.className.split(/\s+/).filter(Boolean)

    this.control = new TomSelect(this.nativeTarget, {
      // The dropdown_input plugin moves the search field into the menu, so the
      // control reads as a select trigger (placeholder/selected item + chevron)
      // rather than an inline text box.
      plugins: ["dropdown_input"],
      maxItems: 1,
      // Curated, server-rendered lists: show every option by default (Tom Select's
      // default of 50 would silently hide the rest). A caller can opt into a cap.
      maxOptions: this.hasMaxOptionsValue ? this.maxOptionsValue : null,
      create: false,
      openOnFocus: true,
      closeAfterSelect: true,
      selectOnTab: false,
      allowEmptyOption: false,
      placeholder: this.placeholderValue,
      render: {
        no_results() {
          return '<div class="panel-combobox__empty" role="status">No results found</div>'
        }
      }
    })

    // The trigger keeps the descriptive prompt; the in-menu search gets its own,
    // plainly-a-search placeholder.
    if (this.control.control_input) this.control.control_input.placeholder = "Search…"

    // Tom Select copied the source <select>'s classes onto .ts-wrapper. The wrapper
    // is styled entirely via the parent `.panel-combobox` scope, never via these
    // copied classes, so all of them are safe — and desirable — to strip: chiefly
    // `panel-native-select`, whose paint must stay on the native <select> for the
    // no-JS fallback but must not bleed onto the enhanced wrapper. Deriving the list
    // from the snapshot keeps this correct if NativeSelect's base class changes.
    this.control.wrapper.classList.remove(...copiedNativeClasses)

    this.decorateFocusableControl()
    this.form = this.nativeTarget.form
    this.form?.addEventListener("reset", this.onFormReset)
    this.element.dataset.enhanced = "true"
  }

  disconnect() {
    this.form?.removeEventListener("reset", this.onFormReset)
    this.control?.destroy()
    this.control = null
    this.form = null
    delete this.element.dataset.enhanced
  }

  syncFromNative() {
    if (!this.control) return

    // Tom Select writes its selection back into the native <select> and fires a
    // native `change`, which re-enters this action. Skip those echoes — only a
    // real external change (form reset, Turbo/server update) leaves the native
    // value diverging from what Tom Select already holds, and only that needs a
    // full re-sync.
    if (this.control.getValue() === this.nativeTarget.value) return

    this.control.sync()
    this.decorateFocusableControl()
  }

  onFormReset() {
    // The reset event fires before the browser restores the select's defaults.
    requestAnimationFrame(() => this.syncFromNative())
  }

  decorateFocusableControl() {
    const input = this.control?.control_input
    if (!input) return

    this.copyAriaAttribute(input, "aria-describedby")
    this.copyAriaAttribute(input, "aria-invalid")
    this.copyAriaAttribute(input, "aria-required")
  }

  copyAriaAttribute(input, name) {
    const value = this.nativeTarget.getAttribute(name)
    if (value) input.setAttribute(name, value)
    else input.removeAttribute(name)
  }
}
