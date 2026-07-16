import { Controller } from "@hotwired/stimulus"
import { autoUpdate, computePosition, flip, offset, shift, size } from "@floating-ui/dom"

const TYPEAHEAD_TIMEOUT_MS = 500

// Progressive enhancement over a native <select>. The native element stays the
// source of truth (it carries the value and submits); this controller hides it,
// reveals a styled trigger + role="listbox" popup, and mirrors every selection
// back to the native element so validation and form submission are unchanged.
export default class extends Controller {
  static targets = ["native", "trigger", "label", "listbox", "option"]
  static values = {
    placement: { type: String, default: "bottom-start" },
    offset: { type: Number, default: 6 },
    placeholder: { type: String, default: "Select…" }
  }

  connect() {
    this.onFormReset = this.onFormReset.bind(this)
    this.cleanupPosition = null
    this.resetFrame = null
    this.typeahead = ""
    this.typeaheadTimer = null

    // Take the native control out of the tab order / a11y tree; the styled trigger
    // now stands in for it. Flipping this attribute is also the CSS switch that
    // hides the native select and shows the trigger.
    this.nativeTarget.setAttribute("tabindex", "-1")
    this.nativeTarget.setAttribute("aria-hidden", "true")
    this.element.dataset.enhanced = "true"

    this.form = this.nativeTarget.form
    this.form?.addEventListener("reset", this.onFormReset)
    this.syncFromNative()
  }

  disconnect() {
    this.form?.removeEventListener("reset", this.onFormReset)
    this.form = null
    if (this.resetFrame) cancelAnimationFrame(this.resetFrame)
    this.resetFrame = null
    this.cancelTypeahead()
    this.stopPositioning()
    if (this.isOpen) this.listboxTarget.hidePopover()
  }

  get isOpen() {
    return this.listboxTarget.matches(":popover-open")
  }

  get enabledOptions() {
    return this.optionTargets.filter(option => option.getAttribute("aria-disabled") !== "true")
  }

  // ── Open / close ───────────────────────────────────────────────────────────

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.isOpen ? this.close() : this.open("selected")
  }

  onTriggerKeydown(event) {
    if (this.triggerTarget.disabled) return

    switch (event.key) {
      case "ArrowUp":
        event.preventDefault()
        this.open("last")
        break
      case "ArrowDown":
      case "Enter":
      case " ":
        event.preventDefault()
        this.open("selected")
        break
      default:
        if (this.isPrintableCharacter(event) && !this.isOpen) {
          this.open("none")
          this.focusByTypeahead(event)
        }
    }
  }

  // focus: "selected" | "first" | "last" | "none"
  open(focus = "selected") {
    if (this.isOpen || this.triggerTarget.disabled) return

    this.listboxTarget.showPopover()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.startPositioning()

    if (focus === "none") return

    requestAnimationFrame(() => {
      const options = this.enabledOptions
      const target =
        focus === "last" ? options.at(-1)
          : focus === "selected" ? (this.selectedOption() || options[0])
            : options[0]
      target?.focus()
    })
  }

  close(restoreFocus = false) {
    this.cancelTypeahead()
    this.stopPositioning()
    if (this.isOpen) this.listboxTarget.hidePopover()
    this.triggerTarget.setAttribute("aria-expanded", "false")
    if (restoreFocus) this.triggerTarget.focus()
  }

  onPopoverToggle(event) {
    if (event.target !== this.listboxTarget || event.newState !== "closed") return
    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.stopPositioning()
  }

  onWindowPointerDown(event) {
    if (this.isOpen && !this.element.contains(event.target)) this.close()
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  onOptionClick(event) {
    const option = event.target.closest('[data-panels-ui--select-menu-target~="option"]')
    if (!option) return

    if (option.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
      return
    }
    this.selectOption(option)
  }

  onListboxKeydown(event) {
    const options = this.enabledOptions
    const current = document.activeElement.closest('[data-panels-ui--select-menu-target~="option"]')
    const index = options.indexOf(current)

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        options[(index + 1) % options.length]?.focus()
        break
      case "ArrowUp":
        event.preventDefault()
        options[(index - 1 + options.length) % options.length]?.focus()
        break
      case "Home":
        event.preventDefault()
        options[0]?.focus()
        break
      case "End":
        event.preventDefault()
        options.at(-1)?.focus()
        break
      case "Enter":
      case " ":
        event.preventDefault()
        if (current) this.selectOption(current)
        break
      case "Escape":
        event.preventDefault()
        this.close(true)
        break
      case "Tab":
        this.close()
        break
      default:
        if (this.isPrintableCharacter(event)) this.focusByTypeahead(event)
    }
  }

  selectOption(option) {
    this.nativeTarget.value = option.dataset.value
    this.nativeTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.nativeTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.syncFromNative()
    this.close(true)
  }

  onNativeChange() {
    this.syncFromNative()
  }

  onFormReset() {
    // The reset event fires before the browser restores the select's defaults.
    if (this.resetFrame) cancelAnimationFrame(this.resetFrame)
    this.resetFrame = requestAnimationFrame(() => {
      this.resetFrame = null
      this.syncFromNative()
    })
  }

  // Mirror the native value into the styled UI. Called on connect, on selection,
  // and whenever the native select changes (programmatically or via form reset).
  syncFromNative() {
    const value = this.nativeTarget.value
    this.optionTargets.forEach(option => {
      option.setAttribute("aria-selected", (option.dataset.value === value).toString())
    })

    const selected = this.selectedOption()
    const label = selected?.querySelector(".panel-select-menu__option-label")?.textContent.trim()
    this.labelTarget.textContent = label || this.placeholderValue
    this.labelTarget.dataset.placeholder = (label ? "false" : "true")
  }

  selectedOption() {
    const value = this.nativeTarget.value
    return this.optionTargets.find(
      option => option.dataset.value === value && option.getAttribute("aria-disabled") !== "true"
    )
  }

  // ── Typeahead ──────────────────────────────────────────────────────────────

  isPrintableCharacter(event) {
    return event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey
  }

  focusByTypeahead(event) {
    event.preventDefault()
    window.clearTimeout(this.typeaheadTimer)
    this.typeahead += event.key.toLocaleLowerCase()

    const options = this.enabledOptions
    const activeIndex = options.indexOf(document.activeElement)
    const ordered = [...options.slice(activeIndex + 1), ...options.slice(0, activeIndex + 1)]
    ordered
      .find(option => option.textContent.trim().toLocaleLowerCase().startsWith(this.typeahead))
      ?.focus()

    this.typeaheadTimer = window.setTimeout(() => {
      this.typeahead = ""
      this.typeaheadTimer = null
    }, TYPEAHEAD_TIMEOUT_MS)
  }

  cancelTypeahead() {
    if (this.typeaheadTimer) window.clearTimeout(this.typeaheadTimer)
    this.typeaheadTimer = null
    this.typeahead = ""
  }

  // ── Positioning (floating-ui) ────────────────────────────────────────────────

  startPositioning() {
    this.stopPositioning()
    this.cleanupPosition = autoUpdate(this.triggerTarget, this.listboxTarget, () => this.position())
  }

  stopPositioning() {
    this.cleanupPosition?.()
    this.cleanupPosition = null
  }

  position() {
    computePosition(this.triggerTarget, this.listboxTarget, {
      placement: this.placementValue,
      strategy: "fixed",
      middleware: [
        offset(this.offsetValue),
        flip(),
        shift({ padding: 8 }),
        size({
          padding: 8,
          apply({ availableHeight, rects, elements }) {
            Object.assign(elements.floating.style, {
              maxHeight: `${Math.max(160, availableHeight)}px`,
              minWidth: `${rects.reference.width}px`
            })
          }
        })
      ]
    }).then(({ x, y, placement }) => {
      Object.assign(this.listboxTarget.style, {
        position: "fixed",
        left: `${x}px`,
        top: `${y}px`
      })
      this.listboxTarget.dataset.placement = placement
    })
  }
}
