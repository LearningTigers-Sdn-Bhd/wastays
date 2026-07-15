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
