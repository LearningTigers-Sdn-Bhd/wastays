import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["word"]
  static values = {
    words: Array,
    interval: { type: Number, default: 100 }
  }

  connect() {
    this.lastIndex = -1
    this.fadeTimeout = null
    this.scrollHandler = this.handleScroll.bind(this)
    window.addEventListener('scroll', this.scrollHandler, { passive: true })
    
    if (this.hasWordTarget) {
      this.wordTarget.style.transition = `opacity ${this.intervalValue}ms ease-in-out`
    }

    // Initialize state
    this.handleScroll()
  }

  disconnect() {
    window.removeEventListener('scroll', this.scrollHandler)
    if (this.fadeTimeout) clearTimeout(this.fadeTimeout)
  }

  handleScroll() {
    const rect = this.element.getBoundingClientRect()
    const windowHeight = window.innerHeight
    
    // Calculate progress based on how much of the track has passed the top of viewport
    const totalScrollable = rect.height - windowHeight
    if (totalScrollable <= 0) return

    const scrollPoint = -rect.top
    const progress = Math.max(0, Math.min(1, scrollPoint / totalScrollable))
    
    const words = this.wordsValue
    // Map progress to index (0.0 - 1.0 -> 0 - length-1)
    const index = Math.min(Math.floor(progress * words.length), words.length - 1)
    
    if (index !== this.lastIndex) {
      this.updateWord(words[index])
      this.lastIndex = index
    }
  }

  updateWord(newWord) {
    if (!this.hasWordTarget) return

    // FAST SCROLL PROTECTION:
    // If we're already mid-fade (fadeTimeout exists), we're scrolling fast.
    // Update text immediately and keep it visible so it doesn't stay "stuck" at 0 opacity.
    if (this.fadeTimeout) {
      clearTimeout(this.fadeTimeout)
      this.wordTarget.textContent = newWord
      this.wordTarget.style.opacity = 1
      this.fadeTimeout = null
      return
    }

    // NORMAL SCROLL:
    // Standard fade out -> change -> fade in
    if (this.wordTarget.textContent !== "" && this.wordTarget.textContent !== newWord) {
      this.wordTarget.style.opacity = 0
      this.fadeTimeout = setTimeout(() => {
        this.wordTarget.textContent = newWord
        this.wordTarget.style.opacity = 1
        this.fadeTimeout = null
      }, this.intervalValue)
    } else {
      this.wordTarget.textContent = newWord
      this.wordTarget.style.opacity = 1
    }
  }
}
