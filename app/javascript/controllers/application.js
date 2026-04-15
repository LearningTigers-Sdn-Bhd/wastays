import { Application } from "@hotwired/stimulus"

const application = Application.start()

// Configure Stimulus development experience
application.debug = false
window.Stimulus   = application

document.addEventListener("turbo:load", () => {
  document.documentElement.classList.remove("landing-loader-active")
})

export { application }
