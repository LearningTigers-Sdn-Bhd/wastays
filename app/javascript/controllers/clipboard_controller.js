import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "source", "button"]
  static values = { text: String, successText: String }

  async copy(event) {
    const button = event.currentTarget || (this.hasButtonTarget ? this.buttonTarget : null)

    const textToCopy =
      (button && button.dataset.clipboardTextValue) ||
      this.textValue ||
      (this.hasSourceTarget ? this.sourceTarget.textContent.trim() : null)

    if (!textToCopy) return

    try {
      await navigator.clipboard.writeText(textToCopy)

      if (this.hasStatusTarget) {
        this.statusTarget.textContent = this.hasSuccessTextValue ? this.successTextValue : "Copied to clipboard."
      }

      if (button) {
        this.showCopiedFeedback(button)
      }
    } catch (_) {
      if (this.hasStatusTarget) {
        this.statusTarget.textContent = "Copy failed. Select and copy the value manually."
      }
    }
  }

  showCopiedFeedback(button) {
    if (button.dataset.copying === "true") return

    const originalHTML = button.innerHTML
    button.dataset.copying = "true"
    const successLabel = this.hasSuccessTextValue ? this.successTextValue : "Copied!"

    button.innerHTML = `
      <svg class="size-3.5 text-emerald-500 inline-block align-text-bottom" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
      <span>${successLabel}</span>
    `

    setTimeout(() => {
      button.innerHTML = originalHTML
      delete button.dataset.copying
    }, 2000)
  }
}
