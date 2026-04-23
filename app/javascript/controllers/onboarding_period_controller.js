import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["trigger", "startInput", "endInput", "display", "popover"]
  static values = { hotelId: Number }

  connect() {
    this.calculate()
    
    this.closeHandler = (e) => {
      if (!this.element.contains(e.target)) {
        this.close()
      }
    }
    document.addEventListener("click", this.closeHandler)
  }

  disconnect() {
    document.removeEventListener("click", this.closeHandler)
  }

  toggle(e) {
    e.preventDefault()
    e.stopPropagation()
    if (this.popoverTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.popoverTarget.classList.remove("hidden")
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "true")
    }

    window.requestAnimationFrame(() => {
      this.positionPopover()
    })
  }

  close() {
    if (this.hasPopoverTarget) {
      this.popoverTarget.classList.add("hidden")
    }
    if (this.hasTriggerTarget) {
      this.triggerTarget.setAttribute("aria-expanded", "false")
    }
  }

  positionPopover() {
    if (!this.hasTriggerTarget || !this.hasPopoverTarget) return

    const triggerRect = this.triggerTarget.getBoundingClientRect()
    const popoverRect = this.popoverTarget.getBoundingClientRect()
    const viewportWidth = window.innerWidth
    const viewportHeight = window.innerHeight
    const offset = 12
    const margin = 16

    let left = triggerRect.left
    if (left + popoverRect.width > viewportWidth - margin) {
      left = Math.max(viewportWidth - popoverRect.width - margin, margin)
    }

    let top = triggerRect.bottom + offset
    if (top + popoverRect.height > viewportHeight - margin) {
      top = Math.max(triggerRect.top - popoverRect.height - offset, margin)
    }

    this.popoverTarget.style.left = `${left}px`
    this.popoverTarget.style.top = `${top}px`
  }

  async save(e) {
    e.preventDefault()
    
    const formData = new FormData()
    formData.append("start_date", this.startInputTarget.value)
    formData.append("end_date", this.endInputTarget.value)
    
    try {
      const response = await fetch(`/admin/hotels/${this.hotelIdValue}/save_onboarding_period`, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept": "text/vnd.turbo-stream.html, application/json"
        },
        body: formData
      })
      
      if (response.ok) {
        const contentType = response.headers.get("content-type") || ""
        if (contentType.includes("text/vnd.turbo-stream.html") && window.Turbo?.renderStreamMessage) {
          window.Turbo.renderStreamMessage(await response.text())
          this.dispatchTrackerFilterRefresh()
        }
        this.close()
        // Optional: show a small success checkmark or toast
      }
    } catch (error) {
      console.error("Failed to save onboarding period:", error)
    }
  }

  update() {
    this.calculate()
  }

  calculate() {
    const start = new Date(this.startInputTarget.value)
    const end = new Date(this.endInputTarget.value)

    if (isNaN(start) || isNaN(end)) {
       this.displayTarget.textContent = "Invalid range"
       return
    }

    if (end < start) {
      this.displayTarget.textContent = "End must be after start"
      return
    }

    const diffTime = Math.abs(end - start)
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24))
    
    let text = ""
    if (diffDays === 0) {
      text = "< 1 day"
    } else if (diffDays < 30) {
      text = `${diffDays} ${diffDays === 1 ? 'day' : 'days'}`
    } else {
      const months = Math.floor(diffDays / 30)
      const days = diffDays % 30
      text = `${months} ${months === 1 ? 'month' : 'months'}`
      if (days > 0) text += ` ${days} ${days === 1 ? 'day' : 'days'}`
    }

    this.displayTarget.textContent = text
  }

  dispatchTrackerFilterRefresh() {
    const searchInput = document.querySelector(
      "[data-controller~='onboarding-tracker-filter'] [data-onboarding-tracker-filter-target='search']"
    )

    if (searchInput) {
      searchInput.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }
}
