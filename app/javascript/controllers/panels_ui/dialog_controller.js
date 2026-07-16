import { Controller } from "@hotwired/stimulus"
import { isTopOverlay, lockScroll, unlockScroll } from "controllers/panels_ui/support/overlay"

// Identifier: panels-ui--dialog  (attached directly to the native <dialog>)
//
// The component renders no trigger — the dialog is opened externally with the
// native invoker commands (`<button command="show-modal" commandfor="id">`) or
// programmatically. Because an open can originate outside this controller's DOM
// scope, we don't rely on an `open` action being wired: a MutationObserver on the
// dialog's `open` attribute lets us react to *every* open path.
//
// On open we lock body scroll and move focus off the native default (the close ✕)
// onto the panel. Escape and focus-trapping are native to <dialog>; we only
// intercept `cancel` to honor `dismissible: false`, and tear down on `close`.
export default class extends Controller {
  static targets = ["panel", "initialFocus"]
  static values = { dismissible: { type: Boolean, default: true } }

  connect() {
    // No native "open" event exists, so watch the attribute showModal() toggles.
    this.observer = new MutationObserver(() => {
      if (this.element.open) this.onOpen()
    })
    this.observer.observe(this.element, { attributes: true, attributeFilter: ["open"] })
    if (this.element.open) this.onOpen() // already open on connect (e.g. Turbo restore)
  }

  disconnect() {
    // Teardown contract: never leave a locked scroll or an open dialog behind.
    this.observer?.disconnect()
    unlockScroll(this.element)
    if (this.element.open) this.element.close()
  }

  // Optional programmatic / in-scope-action open. External triggers use the
  // native invoker command instead; both funnel through onOpen via the observer.
  open() {
    if (!this.element.open) this.element.showModal()
  }

  close() {
    if (this.element.open && isTopOverlay(this.element)) this.element.close()
  }

  onOpen() {
    if (this.element.hasAttribute("data-panels-open")) return // guard double-fire
    this.element.setAttribute("data-panels-open", "")
    lockScroll(this.element)
    // Put focus on meaningful static content at the top so long or structured
    // dialogs are announced from the beginning. A deliberately authored
    // [autofocus] target still takes precedence.
    if (this.hasPanelTarget && !this.element.querySelector("[autofocus]")) {
      const target = this.hasInitialFocusTarget ? this.initialFocusTarget : this.panelTarget
      target.focus()
    }
  }

  // A native <dialog> backdrop click lands on the dialog element itself; clicks on
  // the inner content have a descendant target. So target === element means backdrop.
  backdropClose(event) {
    if (this.dismissibleValue && isTopOverlay(this.element) && event.target === this.element) this.close()
  }

  // Native `cancel` fires on Escape. Only the top overlay may respond.
  onCancel(event) {
    if (!this.dismissibleValue || !isTopOverlay(this.element)) event.preventDefault()
  }

  // Native `close` fires once the dialog is actually closed by any path — unlock
  // scroll and reset the styling hook here so every close route is covered.
  onClose() {
    this.element.removeAttribute("data-panels-open")
    unlockScroll(this.element)
  }
}
