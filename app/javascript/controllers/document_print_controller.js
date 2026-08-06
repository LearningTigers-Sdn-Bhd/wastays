import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { url: String }

  connect() {
    this.frame = null
    this.cleanupTimer = null
  }

  disconnect() {
    this.cleanup()
  }

  print(event) {
    event.preventDefault()
    if (this.frame) return

    this.setBusy(true, "Preparing official form…")
    const frame = document.createElement("iframe")
    frame.src = this.urlValue
    frame.title = "Guest Registration Card print frame"
    frame.tabIndex = -1
    frame.setAttribute("aria-hidden", "true")
    frame.dataset.documentPrintFrame = "true"
    frame.className = "pointer-events-none fixed bottom-0 right-0 h-px w-px border-0 opacity-0"
    frame.addEventListener("load", () => this.printFrame(frame), { once: true })
    frame.addEventListener("error", () => this.fail(), { once: true })
    this.frame = frame
    document.body.appendChild(frame)
  }

  printFrame(frame) {
    if (frame !== this.frame) return

    const printWindow = frame.contentWindow
    if (!printWindow) {
      this.fail()
      return
    }

    const finish = () => this.cleanup()
    printWindow.addEventListener("afterprint", finish, { once: true })
    this.cleanupTimer = window.setTimeout(finish, 60000)
    this.dispatch("ready", { detail: { frame } })

    try {
      printWindow.focus()
      printWindow.print()
    } catch (_error) {
      this.fail()
    }
  }

  fail() {
    this.cleanup(false)
    this.setBusy(false, "Official form could not be prepared. Try again.")
  }

  cleanup(clearStatus = true) {
    if (this.cleanupTimer) window.clearTimeout(this.cleanupTimer)
    this.cleanupTimer = null
    this.frame?.remove()
    this.frame = null
    this.setBusy(false, clearStatus ? "" : (this.statusElement?.textContent || ""))
  }

  setBusy(busy, message) {
    this.buttonTarget.disabled = busy
    const status = this.statusElement
    if (!status) return

    status.textContent = message
    status.classList.toggle("hidden", message.length === 0)
  }

  get statusElement() {
    return document.querySelector("[data-document-print-status]")
  }
}
