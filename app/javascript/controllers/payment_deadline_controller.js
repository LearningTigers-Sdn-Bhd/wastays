import { Controller } from "@hotwired/stimulus"

// The time an agent has left to pay before the rooms are released.
//
// Deliberately not the `countdown` controller: that one counts a quote hold in
// minutes and seconds and reloads the page when it lapses, which is right for a
// ten-minute hold on a page the guest is sitting on. A payment deadline runs for
// days, is read on a list of many bookings, and must not reload anything --
// nothing on the page changes at the moment it lapses, because the sweeper runs
// on its own schedule.
//
// The server renders the exact deadline as text; this only adds the relative
// part, so the page still says something true with JavaScript off.
export default class extends Controller {
  static values = { dueAt: String }
  static targets = ["remaining"]

  connect() {
    this.dueAt = Date.parse(this.dueAtValue)
    if (Number.isNaN(this.dueAt)) return

    this.render()
    // A deadline in days does not need a per-second tick.
    this.timer = setInterval(() => this.render(), 30_000)
  }

  disconnect() {
    if (this.timer) clearInterval(this.timer)
  }

  render() {
    if (!this.hasRemainingTarget) return

    const remaining = this.dueAt - Date.now()
    this.element.dataset.state = this.state(remaining)
    this.remainingTarget.textContent = this.label(remaining)
  }

  // "Overdue" rather than "released": the sweeper decides when the rooms
  // actually go back on sale, and claiming otherwise here would be a guess.
  state(remaining) {
    if (remaining <= 0) return "overdue"
    if (remaining <= 6 * 3600_000) return "urgent"
    return "pending"
  }

  label(remaining) {
    if (remaining <= 0) return "Overdue"

    const minutes = Math.floor(remaining / 60_000)
    const hours = Math.floor(minutes / 60)
    const days = Math.floor(hours / 24)

    if (days >= 1) return `${days}d ${hours % 24}h left`
    if (hours >= 1) return `${hours}h ${minutes % 60}m left`
    return `${Math.max(minutes, 1)}m left`
  }
}
