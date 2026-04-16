import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slide"]
  static values = {
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.currentIndex = 0
    this.show(this.currentIndex)
    this.startRotation()
  }

  disconnect() {
    this.stopRotation()
  }

  startRotation() {
    if (this.slideTargets.length < 2) return

    this.stopRotation()
    this.timer = window.setInterval(() => {
      this.currentIndex = (this.currentIndex + 1) % this.slideTargets.length
      this.show(this.currentIndex)
    }, this.intervalValue)
  }

  stopRotation() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }

  show(activeIndex) {
    this.slideTargets.forEach((slide, index) => {
      slide.classList.toggle("opacity-100", index === activeIndex)
      slide.classList.toggle("opacity-0", index !== activeIndex)
    })
  }
}
