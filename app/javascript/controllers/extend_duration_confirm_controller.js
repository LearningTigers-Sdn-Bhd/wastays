import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["guestName", "currentCheckOut", "newCheckOut"]

  connect() {
    this.pendingAction = null
    this.overlayRequestId = 0
    this.boundOpen = this.open.bind(this)
    window.addEventListener("booking-timeline-board:confirm-extend", this.boundOpen)
  }

  disconnect() {
    window.removeEventListener("booking-timeline-board:confirm-extend", this.boundOpen)
  }

  async open(event) {
    this.pendingAction = event.detail
    this.guestNameTarget.textContent = event.detail.guestName || "-"
    this.currentCheckOutTarget.textContent = event.detail.currentCheckOut || "-"
    this.newCheckOutTarget.textContent = event.detail.newCheckOut || "-"

    // Dispatch global event to open the extend duration overlay
    window.dispatchEvent(new CustomEvent("booking-timeline-board:open-extend-duration"))
  }

  async confirm() {
    if (!this.pendingAction) return

    try {
      const response = await this.pendingAction.onConfirm()
      this.close()
      this.pendingAction.onSuccess?.(response)
    } catch (error) {
      console.error("Error extending stay:", error)
      this.pendingAction.onError?.(error)
    } finally {
      this.pendingAction = null
    }
  }

  cancel() {
    this.pendingAction?.onCancel?.()
    this.pendingAction = null
    this.close()
  }

  close() {
    window.dispatchEvent(new CustomEvent("booking-timeline-board:close-all"))
  }
}
