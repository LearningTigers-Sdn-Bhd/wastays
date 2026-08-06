import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"
import { autoUpdate, computePosition, flip, offset, shift, size } from "@floating-ui/dom"

// Ceiling mirrors the `max-height` in panel/combobox.css: the menu is capped at a
// readable height rather than growing to fill whatever room the viewport offers.
// The floor keeps a usable list when it is squeezed against an edge.
const MENU_MAX_HEIGHT = 320
const MIN_MENU_HEIGHT = 140

export default class extends Controller {
  static targets = ["native"]
  static values = { placeholder: String, maxOptions: Number, emptyText: String, allowEmptyOption: Boolean }

  connect() {
    this.onFormReset = this.onFormReset.bind(this)

    // Snapshot the native's classes before Tom Select copies them onto .ts-wrapper
    // during construction (it also mutates this classList, e.g. hidden-accessible —
    // so it must be read now). See the strip below.
    const copiedNativeClasses = this.nativeTarget.className.split(/\s+/).filter(Boolean)

    this.control = new TomSelect(this.nativeTarget, this.tomSelectOptions())

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
    this.startMenuPositioning()
    this.form = this.nativeTarget.form
    this.form?.addEventListener("reset", this.onFormReset)
    this.element.dataset.enhanced = "true"
  }

  // ── Menu positioning (floating-ui) ──────────────────────────────────────────
  //
  // Tom Select only positions the menu itself when it is parented to <body>,
  // which is not an option here: these render inside Sheets, and the dialog owns
  // the top layer, so a body-parented menu would paint behind it. Left as CSS
  // absolute positioning, the menu could neither flip nor know how much room it
  // had, so near the bottom of a scrolling sheet it opened downwards into the
  // overflow. This is the same middleware stack PanelsUI::SelectMenu uses.
  startMenuPositioning() {
    this.onDropdownOpen = () => {
      this.stopMenuPositioning()
      this.cleanupPosition = autoUpdate(this.control.control, this.control.dropdown, () => this.positionMenu())
    }
    this.onDropdownClose = () => this.stopMenuPositioning()

    this.control.on("dropdown_open", this.onDropdownOpen)
    this.control.on("dropdown_close", this.onDropdownClose)
  }

  stopMenuPositioning() {
    this.cleanupPosition?.()
    this.cleanupPosition = null
  }

  positionMenu() {
    const menu = this.control?.dropdown
    const content = this.control?.dropdown_content
    if (!menu || !content) return

    computePosition(this.control.control, menu, {
      placement: "bottom-start",
      strategy: "fixed",
      middleware: [
        offset(6),
        flip(),
        shift({ padding: 8 }),
        size({
          padding: 8,
          apply({ availableHeight, rects, elements }) {
            // The menu tracks the control's width. Without this it is
            // shrink-to-fit, and a multi-select's selected-pills panel will
            // happily stretch it across the whole viewport.
            Object.assign(elements.floating.style, { width: `${rects.reference.width}px` })

            // availableHeight covers the whole menu; the scrollable option list
            // gets what is left after the pinned search field and, on a
            // multi-select, the selected-badges panel — capped at the design
            // ceiling so a tall viewport does not produce a full-height menu.
            const chrome = elements.floating.offsetHeight - content.offsetHeight
            const room = Math.min(MENU_MAX_HEIGHT, availableHeight - chrome)
            Object.assign(content.style, { maxHeight: `${Math.max(MIN_MENU_HEIGHT, room)}px` })
          }
        })
      ]
    }).then(({ x, y, placement }) => {
      Object.assign(menu.style, {
        position: "fixed",
        left: `${x}px`,
        top: `${y}px`,
        // The stylesheet pins the menu under the control with `inset-inline: 0`;
        // clear the trailing edge or it stretches to the old anchor's width.
        right: "auto",
        bottom: "auto"
      })
      menu.dataset.placement = placement
    })
  }

  // The Tom Select configuration. Extracted so subclasses (e.g. MultiSelect) can
  // override individual options while inheriting every other behaviour verbatim.
  tomSelectOptions() {
    return {
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
      // A blank-valued option is the placeholder by default; when the caller says
      // blank is a real choice ("Unassigned"), keep it in the menu instead.
      allowEmptyOption: this.allowEmptyOptionValue,
      placeholder: this.placeholderValue,
      render: {
        no_results: () => {
          const text = this.hasEmptyTextValue ? this.emptyTextValue : "No results found"
          return `<div class="panel-combobox__empty" role="status">${this.escapeHtml(text)}</div>`
        }
      }
    }
  }

  // Escape developer-provided empty text before interpolating it into the menu.
  escapeHtml(value) {
    const div = document.createElement("div")
    div.textContent = value
    return div.innerHTML
  }

  disconnect() {
    this.stopMenuPositioning()
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
    if (this.valueMatchesNative()) return

    this.control.sync()
    this.decorateFocusableControl()
  }

  // True when Tom Select's selection already equals the native <select>. Single
  // value here; MultiSelect overrides this to compare the selected-value sets.
  valueMatchesNative() {
    return this.control.getValue() === this.nativeTarget.value
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
