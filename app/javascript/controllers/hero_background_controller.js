import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slide"]
  static values = {
    interval: { type: Number, default: 5000 }
  }

  connect() {
    this.currentIndex = 0
    this.show(this.currentIndex)
    this.preloadDeferredSlides()
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
    this.ensureSlideSource(this.slideTargets[activeIndex])

    this.slideTargets.forEach((slide, index) => {
      slide.classList.toggle("opacity-100", index === activeIndex)
      slide.classList.toggle("opacity-0", index !== activeIndex)
    })
  }

  preloadDeferredSlides() {
    if (this.slideTargets.length < 2) return

    const hydrate = () => {
      this.slideTargets.forEach((slide, index) => {
        if (index === 0) return
        this.ensureSlideSource(slide)
      })
    }

    if ("requestIdleCallback" in window) {
      window.requestIdleCallback(hydrate, { timeout: 1200 })
      return
    }

    window.setTimeout(hydrate, 700)
  }

  ensureSlideSource(slide) {
    if (!slide || slide.getAttribute("src")) return

    const source = slide.dataset.src
    if (source) slide.setAttribute("src", source)
  }
}
