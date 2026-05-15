import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["url", "copyButton"]

  print(event) {
    event.preventDefault()
    window.print()
  }

  copy(event) {
    event.preventDefault()

    navigator.clipboard.writeText(this.urlTarget.innerText).then(() => {
      this.showCopiedState()
    }).catch((error) => {
      console.error("Failed to copy concierge URL:", error)
    })
  }

  showCopiedState() {
    const originalContent = this.copyButtonTarget.innerHTML

    this.copyButtonTarget.innerHTML = `
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7"/></svg>
      Copied
    `

    setTimeout(() => {
      this.copyButtonTarget.innerHTML = originalContent
    }, 2000)
  }
}
