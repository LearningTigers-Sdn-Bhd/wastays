import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.playChime()
    this.dismissTimer = setTimeout(() => this.dismiss(), 3000)
  }

  disconnect() {
    if (this.dismissTimer) clearTimeout(this.dismissTimer)
  }

  dismiss() {
    this.element.classList.add("opacity-0", "translate-y-1")
    setTimeout(() => this.element.remove(), 250)
  }

  playChime() {
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext
      if (!AudioContextClass) return

      const context = new AudioContextClass()
      const oscillator = context.createOscillator()
      const gain = context.createGain()
      oscillator.type = "sine"
      oscillator.frequency.setValueAtTime(880, context.currentTime)
      gain.gain.setValueAtTime(0.0001, context.currentTime)
      gain.gain.exponentialRampToValueAtTime(0.03, context.currentTime + 0.01)
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.18)
      oscillator.connect(gain)
      gain.connect(context.destination)
      oscillator.start()
      oscillator.stop(context.currentTime + 0.2)
    } catch (_) {}
  }
}
