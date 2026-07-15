import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "remarkInput", "remarkPrint", "remarkHidden",
    "notesInput", "notesPrint", "notesHidden",
    "status"
  ]
  static values = { url: String }

  connect() {
    this.updateRemark()
    this.updateNotes()
  }

  updateRemark() {
    if (this.hasRemarkInputTarget) {
      const val = this.remarkInputTarget.value
      if (this.hasRemarkPrintTarget) this.remarkPrintTarget.textContent = val
      if (this.hasRemarkHiddenTarget) this.remarkHiddenTarget.value = val
    }
  }

  updateNotes() {
    if (this.hasNotesInputTarget) {
      const val = this.notesInputTarget.value
      if (this.hasNotesPrintTarget) this.notesPrintTarget.textContent = val
      if (this.hasNotesHiddenTarget) this.notesHiddenTarget.value = val
    }
  }

  onInput(event) {
    if (event.target === this.remarkInputTarget) {
      this.updateRemark()
    } else if (event.target === this.notesInputTarget) {
      this.updateNotes()
    }

    // Hide any previous status message immediately while typing is in progress
    if (this.hasStatusTarget) {
      this.statusTarget.className = "text-xs font-bold text-emerald-600 flex items-center gap-1.5 opacity-0 transition-opacity duration-200"
    }

    clearTimeout(this.debounceTimeout)
    this.debounceTimeout = setTimeout(() => {
      this.save()
    }, 500)
  }

  async save() {
    if (!this.hasUrlValue) return

    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
    try {
      const response = await fetch(this.urlValue, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({
          guest_registration_card: {
            special_requests: this.hasRemarkInputTarget ? this.remarkInputTarget.value : "",
            internal_notes: this.hasNotesInputTarget ? this.notesInputTarget.value : ""
          }
        })
      })

      if (response.ok) {
        // Only show the green "Saved" message after it has successfully finished saving
        if (this.hasStatusTarget) {
          this.statusTarget.innerHTML = `
            <svg class="h-4 w-4 shrink-0 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke-width="2.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 12.75 6 6 9-13.5" />
            </svg>
            Saved
          `
          this.statusTarget.className = "text-xs font-bold text-emerald-600 flex items-center gap-1.5 opacity-100 transition-opacity duration-200"
          
          clearTimeout(this.fadeTimeout)
          this.fadeTimeout = setTimeout(() => {
            this.statusTarget.className = "text-xs font-bold text-emerald-600 flex items-center gap-1.5 opacity-0 transition-opacity duration-500"
          }, 2000)
        }
      } else {
        this.showError()
      }
    } catch (error) {
      console.error("Auto-save failed", error)
      this.showError()
    }
  }

  showError() {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = "Error saving changes."
      this.statusTarget.className = "text-xs font-bold text-red-600 flex items-center gap-1.5 opacity-100 transition-opacity duration-200"
    }
  }

  disconnect() {
    clearTimeout(this.debounceTimeout)
    clearTimeout(this.fadeTimeout)
  }
}
