// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "turbo_confirm"

console.log("Wastays Application JS loaded")

async function initializePreline() {
  const enabled = document.body?.dataset?.prelineEnabled !== "false"
  if (!enabled) return

  try {
    await import("preline")

    if (window.HSStaticMethods?.autoInit) {
      window.HSStaticMethods.autoInit()
    }
  } catch (error) {
    console.warn("Preline initialization failed", error)
  }
}

document.addEventListener("turbo:load", initializePreline)
document.addEventListener("turbo:frame-render", initializePreline)

// Custom Turbo Stream Actions
Turbo.StreamActions.reload = function() {
  Turbo.visit(window.location.href, { action: "replace" })
}
