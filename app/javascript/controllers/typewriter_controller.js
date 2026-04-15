import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    words: Array,
    typingSpeed: { type: Number, default: 90 },
    deletingSpeed: { type: Number, default: 55 },
    pauseDelay: { type: Number, default: 1400 }
  }

  connect() {
    this.wordIndex = 0
    this.charIndex = 0
    this.isDeleting = false
    this.tick()
  }

  disconnect() {
    if (this.timer) {
      window.clearTimeout(this.timer)
      this.timer = null
    }
  }

  tick() {
    const words = this.wordsValue || []
    if (words.length === 0) return

    const currentWord = words[this.wordIndex % words.length]

    if (this.isDeleting) {
      this.charIndex -= 1
    } else {
      this.charIndex += 1
    }

    this.element.textContent = currentWord.slice(0, this.charIndex)

    let delay = this.isDeleting ? this.deletingSpeedValue : this.typingSpeedValue

    if (!this.isDeleting && this.charIndex === currentWord.length) {
      this.isDeleting = true
      delay = this.pauseDelayValue
    } else if (this.isDeleting && this.charIndex === 0) {
      this.isDeleting = false
      this.wordIndex += 1
      delay = 250
    }

    this.timer = window.setTimeout(() => this.tick(), delay)
  }
}
