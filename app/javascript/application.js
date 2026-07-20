// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

console.log("Wastays Application JS loaded")

// Custom Turbo Stream Actions
Turbo.StreamActions.reload = function() {
  Turbo.visit(window.location.href, { action: "replace" })
}

Turbo.StreamActions.redirect = function() {
  Turbo.visit(this.getAttribute("url"))
}

Turbo.StreamActions.complete_offcanvas = function() {
  const container = document.getElementById("offcanvas_drawer_container")
  const controller = container && window.Stimulus?.getControllerForElementAndIdentifier(container, "offcanvas")
  const url = this.getAttribute("url")

  if (controller) {
    controller.complete(url)
  } else if (url) {
    Turbo.visit(url, { action: "replace" })
  }
}

// Sheet analog of complete_offcanvas for HotelPortal::Bookings::Actions.
// Closes the booking-action Sheet (the native <dialog> restores focus to the
// invoker and panels-ui--sheet-frame clears the frame on close), then navigates
// to the return destination after the exit transition.
Turbo.StreamActions.complete_sheet = function() {
  const frameId = this.getAttribute("target") || "booking_action_sheet"
  const frame = document.getElementById(frameId)
  const dialog = frame?.querySelector("dialog")
  const controller = dialog && window.Stimulus?.getControllerForElementAndIdentifier(dialog, "panels-ui--sheet")
  const url = this.getAttribute("url")

  if (controller) {
    controller.close()
  } else {
    dialog?.close()
  }

  if (url) {
    setTimeout(() => Turbo.visit(url, { action: "replace" }), 325)
  }
}
