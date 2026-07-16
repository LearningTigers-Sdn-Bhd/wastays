import { Controller } from "@hotwired/stimulus"

// Bridges a Turbo form submission to the toast system:
//   turbo:submit-start -> show a persistent "loading" toast
//   turbo:submit-end   -> dismiss it, then show a success/error toast
// Attached to the stable section wrapper (not the form), so it survives the
// Turbo frame swapping the form out on each response.
export default class extends Controller {
  connect() {
    this.loadingId = null
  }

  start() {
    this.dismissLoading()
    this.loadingId = window.toast?.("Saving reservation…", {
      type: "loading",
      description: "Sending your request to the server.",
      duration: false
    })
  }

  end(event) {
    this.dismissLoading()

    if (event.detail?.success) {
      window.toast?.("Reservation saved", {
        type: "success",
        description: "Your booking request was recorded."
      })
    } else {
      window.toast?.("Couldn't save reservation", {
        type: "error",
        description: "Check the highlighted fields and try again."
      })
    }
  }

  dismissLoading() {
    if (!this.loadingId) return
    window.dismissToast?.(this.loadingId)
    this.loadingId = null
  }
}
