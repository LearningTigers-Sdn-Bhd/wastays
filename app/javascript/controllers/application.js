import { Application } from "@hotwired/stimulus"

const application = Application.start()

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

export { application }
