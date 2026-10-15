import { Controller } from "@hotwired/stimulus"

// Shows whether the tablet is actually listening, and tells the server so.
//
// This is the failure that matters in a lobby: a tablet whose socket has
// dropped, or whose screen has slept, looks identical to one that is waiting.
// Staff press send at the desk, nothing happens, and there is nothing on either
// screen to say why. So the idle screen states it outright -- and beats back to
// the server, so the desk's tablet picker can say it too. Without the beat the
// server only knows this page was loaded once, which is not the same question.
//
// Cable connection state is not exposed as an event, so this reads the document
// instead: turbo-cable-stream-source carries a `connected` attribute that
// Turbo sets and clears, and the browser tells us separately when the tab is
// hidden or the network drops.
export default class extends Controller {
  static targets = ["status", "statusLabel"]
  static classes = ["online", "offline"]
  static values = { heartbeatUrl: String, heartbeatInterval: { type: Number, default: 20000 } }

  connect() {
    this.refresh = this.refresh.bind(this)
    this.beat = this.beat.bind(this)

    this.observer = new MutationObserver(this.refresh)
    document.querySelectorAll("turbo-cable-stream-source").forEach((source) => {
      this.observer.observe(source, { attributes: true, attributeFilter: ["connected"] })
    })

    window.addEventListener("online", this.refresh)
    window.addEventListener("offline", this.refresh)
    document.addEventListener("visibilitychange", this.refresh)

    // The stream source connects a moment after the page does, so an immediate
    // read would always report offline.
    this.timer = setInterval(this.refresh, 2000)
    this.heartbeatTimer = setInterval(this.beat, this.heartbeatIntervalValue)
    this.refresh()
  }

  disconnect() {
    this.observer?.disconnect()
    clearInterval(this.timer)
    clearInterval(this.heartbeatTimer)
    window.removeEventListener("online", this.refresh)
    window.removeEventListener("offline", this.refresh)
    document.removeEventListener("visibilitychange", this.refresh)
  }

  refresh() {
    const listening = this.isListening()

    this.statusLabelTarget.textContent = listening ? "Ready" : "Not connected — reload this page"

    if (this.hasStatusTarget && this.hasOnlineClass && this.hasOfflineClass) {
      this.statusTarget.classList.toggle(this.onlineClass, listening)
      this.statusTarget.classList.toggle(this.offlineClass, !listening)
    }
  }

  // Deliberately silent on failure. A missed beat is already the signal -- the
  // desk stops seeing this tablet as live -- so there is nothing useful to put
  // on a screen a guest may be looking at.
  beat() {
    if (!this.hasHeartbeatUrlValue || !this.isListening()) return

    fetch(this.heartbeatUrlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrfToken },
      keepalive: true
    }).catch(() => {})
  }

  // The desk is told a tablet is live only when its stream is genuinely up, so
  // the beat and the on-screen status answer the same question.
  isListening() {
    const sources = Array.from(document.querySelectorAll("turbo-cable-stream-source"))
    return navigator.onLine && sources.some((source) => source.hasAttribute("connected"))
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
