import { Turbo } from "@hotwired/turbo-rails"

class TurboConfirm {
  constructor() {
    this.confirmModal = document.getElementById("turbo-confirm-modal")
    this.confirmTitle = document.getElementById("turbo-confirm-title")
    this.confirmMessage = document.getElementById("turbo-confirm-message")
    this.confirmButton = document.getElementById("turbo-confirm-button")
    this.cancelButton = document.getElementById("turbo-cancel-button")
    
    if (this.confirmModal) {
      this.setup()
    }
  }

  setup() {
    Turbo.setConfirmMethod((message, element) => {
      let title = element.dataset.turboConfirmTitle || "Confirm Action"
      this.confirmTitle.textContent = title
      this.confirmMessage.textContent = message
      
      // Update button color based on action type if provided
      if (element.dataset.turboConfirmColor === 'red') {
        this.confirmButton.className = "inline-flex items-center rounded-xl bg-red-600 px-4 py-2.5 text-sm font-bold text-white transition hover:bg-red-700 disabled:opacity-50 disabled:pointer-events-none"
      } else {
        this.confirmButton.className = "inline-flex items-center rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-bold text-white transition hover:bg-blue-700 disabled:opacity-50 disabled:pointer-events-none"
      }

      this.confirmModal.classList.remove("hidden")
      this.confirmModal.classList.add("flex")
      
      return new Promise((resolve) => {
        this.confirmButton.onclick = () => {
          this.hide()
          resolve(true)
        }
        
        this.cancelButton.onclick = () => {
          this.hide()
          resolve(false)
        }

        this.confirmModal.onclick = (event) => {
          if (event.target === this.confirmModal) {
            this.hide()
            resolve(false)
          }
        }

        // Close on ESC
        const onEsc = (e) => {
          if (e.key === "Escape") {
            this.hide()
            window.removeEventListener("keydown", onEsc)
            resolve(false)
          }
        }
        window.addEventListener("keydown", onEsc)
      })
    })
  }

  hide() {
    this.confirmModal.classList.add("hidden")
    this.confirmModal.classList.remove("flex")
    this.confirmModal.onclick = null
  }
}

// Initialize on turbo:load
document.addEventListener("turbo:load", () => {
  new TurboConfirm()
})
