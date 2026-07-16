import { Application } from "@hotwired/stimulus"

const application = Application.start()
window.Stimulus = application

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

const clearLandingLoaderScrollLock = () => {
  document.documentElement.classList.remove("landing-loader-active")
}

document.addEventListener("turbo:before-render", clearLandingLoaderScrollLock)
document.addEventListener("turbo:render", clearLandingLoaderScrollLock)

document.addEventListener("turbo:load", () => {
  if (!document.querySelector("[data-controller~='landing-loader']")) {
    clearLandingLoaderScrollLock()
  }
})

// Track the visit action ("advance", "replace", or "restore") so turbo:load
// can tell a fresh link-click navigation apart from a back/forward restore.
let lastVisitAction = "advance"
document.addEventListener("turbo:visit", (event) => {
  lastVisitAction = event.detail.action
})

// Turbo intercepts same-page anchor links (e.g. nav "Why WhatsApp" -> /#whatsapp)
// as a same-page visit: the URL updates but the browser never performs the
// native jump-to-fragment scroll. Do it manually on every load.
//
// For a plain link click to a new page with no hash (an "advance" visit),
// force scroll-to-top explicitly rather than relying on Turbo's implicit
// default — something in the page (e.g. the third-party chat widget script)
// can otherwise leave the new page scrolled to the previous position.
// Back/forward navigation ("restore") is left alone so its native scroll
// restoration keeps working.
const scrollToHashTarget = () => {
  if (window.location.hash) {
    const target = document.getElementById(window.location.hash.slice(1))
    if (!target) return

    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" })
    return
  }

  if (lastVisitAction === "advance") {
    window.scrollTo(0, 0)
  }
}

document.addEventListener("turbo:load", scrollToHashTarget)

export { application }
