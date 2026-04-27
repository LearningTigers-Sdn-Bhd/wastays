import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["word"]
  static values = {
    words: Array,
    interval: { type: Number, default: 2500 }
  }

  connect() {
    this.index = 0
    this.timer = null
    this.setupObserver()
  }

  disconnect() {
    this.stopLoop()
    if (this.observer) {
      this.observer.disconnect()
    }
  }

  setupObserver() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            this.startLoop()
          } else {
            this.stopLoop()
          }
        })
      },
      { threshold: 0.1 }
    )
    this.observer.observe(this.element)
  }

  startLoop() {
    if (this.timer) return
    this.timer = setInterval(() => this.nextWord(), this.intervalValue)
  }

  stopLoop() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  nextWord() {
    if (!this.hasWordTarget || !this.wordsValue.length) return

    this.index = (this.index + 1) % this.wordsValue.length
    const nextWord = this.wordsValue[this.index]

    this.animateTransition(nextWord)
  }

  animateTransition(newWord) {
    const el = this.wordTarget
    
    // Phase 1: Fade out and slide up
    el.style.transition = "all 0.4s cubic-bezier(0.4, 0, 0.2, 1)"
    el.style.opacity = "0"
    el.style.transform = "translateY(-12px)"

    setTimeout(() => {
      // Phase 2: Switch text and reset position (invisible)
      el.textContent = newWord
      el.style.transition = "none"
      el.style.transform = "translateY(12px)"
      
      // Force reflow
      el.offsetHeight

      // Phase 3: Fade in and slide to center
      el.style.transition = "all 0.4s cubic-bezier(0.4, 0, 0.2, 1)"
      el.style.opacity = "1"
      el.style.transform = "translateY(0)"
    }, 400)
  }
}
