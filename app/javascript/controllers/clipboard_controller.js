import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]
  static values = {
    successText: { type: String, default: "Copied!" }
  }

  copy(event) {
    event.preventDefault()
    
    const text = this.sourceTarget.innerText || this.sourceTarget.value
    
    navigator.clipboard.writeText(text).then(() => {
      this.showSuccess()
    }).catch(err => {
      console.error('Failed to copy: ', err)
    })
  }

  showSuccess() {
    const button = this.buttonTarget
    const originalContent = button.innerHTML
    const originalClasses = Array.from(button.classList)
    
    // Success state
    button.innerHTML = `
      <svg class="w-3 h-3" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
      <span>${this.successTextValue}</span>
    `
    // Add success colors, remove neutral ones
    button.classList.add("bg-status-success/10", "text-status-success", "border-status-success/20")
    
    setTimeout(() => {
      // Revert content
      button.innerHTML = originalContent
      // Revert classes: remove success specific ones
      button.classList.remove("bg-status-success/10", "text-status-success", "border-status-success/20")
    }, 2000)
  }
}
