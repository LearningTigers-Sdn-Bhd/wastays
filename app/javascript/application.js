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

// Handle manual overlay triggers for elements that might not have been auto-initialized
document.addEventListener("click", (event) => {
  const trigger = event.target.closest("[data-hs-overlay]")
  if (!trigger) return

  const targetSelector = trigger.getAttribute("data-hs-overlay")
  const target = document.querySelector(targetSelector)
  if (!target) return

  // If HSOverlay isn't initialized, or if the overlay is hidden, trigger it
  if (window.HSOverlay) {
    const instance = window.HSOverlay.getInstance(target, true)
    if (!instance || target.classList.contains("hidden")) {
      window.HSOverlay.open(target)
    }
  } else {
    // Fallback if Preline is completely missing
    target.classList.remove("hidden")
    target.classList.add("open", "hs-overlay-open")
    const backdrop = document.createElement("div")
    backdrop.className = "hs-overlay-backdrop fixed inset-0 z-[119] bg-slate-950/55 backdrop-blur-sm"
    backdrop.id = `${target.id}-backdrop`
    document.body.appendChild(backdrop)
  }
})

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
