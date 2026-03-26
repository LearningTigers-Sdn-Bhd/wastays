// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "turbo_confirm"

document.addEventListener("turbo:load", () => {
  // Keep Stimulus interactions working even if CDN preline fails to load.
  import("preline")
    .then(() => {
      if (typeof HSStaticMethods !== "undefined") {
        HSStaticMethods.autoInit()
      }
    })
    .catch(() => {})
})
