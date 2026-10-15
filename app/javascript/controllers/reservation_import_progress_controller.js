import { Controller } from "@hotwired/stimulus"

// Keeps the import progress page honest when the broadcast does not arrive.
//
// The job pushes progress over a Turbo stream, which is the fast path. But a
// socket can be missing for reasons the page cannot see -- a dropped
// connection, a cable adapter that does not reach the worker process -- and an
// import that is running while the screen says 0% is worse than a slow screen.
// So this re-fetches the page on a slow timer, and stops the moment the markup
// says the run has finished.
export default class extends Controller {
  static values = { interval: { type: Number, default: 5000 } }

  connect() {
    this.#schedule()
  }

  disconnect() {
    this.#clear()
  }

  #schedule() {
    this.#clear()
    if (!this.#running()) return

    this.timer = setTimeout(() => this.#refresh(), this.intervalValue)
  }

  #refresh() {
    if (!this.#running()) return

    // A replace keeps the entry out of history, so Back does not walk through
    // every poll the page made.
    window.Turbo?.visit(window.location.href, { action: "replace" })
  }

  #running() {
    return this.element.querySelector("[data-import-running='true']") !== null
  }

  #clear() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = null
  }
}
