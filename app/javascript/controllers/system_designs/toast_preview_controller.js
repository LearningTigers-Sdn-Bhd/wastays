import { Controller } from "@hotwired/stimulus"

const VARIANT_COPY = {
  default: { title: "Note", description: "A neutral, low-priority update." },
  primary: { title: "Heads up", description: "Something worth a glance." },
  info: { title: "New feature available", description: "Refresh to pick up the latest changes." },
  success: { title: "Booking confirmed", description: "A confirmation email is on its way." },
  warning: { title: "Rate limit approaching", description: "You're close to today's quota." },
  danger: { title: "Payment failed", description: "The card was declined by the issuer." }
}

export default class extends Controller {
  showVariant(event) {
    const variant = event.currentTarget.dataset.toastVariant
    const copy = VARIANT_COPY[variant]
    window.toast(copy.title, { type: variant, description: copy.description })
  }

  showWithAction() {
    window.toast("Booking flagged for review", {
      type: "warning",
      description: "A duplicate charge was detected on this stay.",
      action: { label: "Review", onClick: () => window.toast("Review opened", { type: "info" }) }
    })
  }

  showDescription() {
    window.toast("Guest registered", {
      type: "success",
      description: "The guest profile is ready for check-in."
    })
  }
}
