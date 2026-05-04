import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.reinitialize()
    document.addEventListener("turbo:before-render", this.preserveWidget)
  }

  disconnect() {
    document.removeEventListener("turbo:before-render", this.preserveWidget)
  }

  preserveWidget = (event) => {
    // Manually copy the widget content to the new body if it's missing
    const oldContainer = document.getElementById("abw-btn-cont")
    const newContainer = event.detail.newBody.querySelector("#abw-btn-cont")
    
    if (oldContainer && newContainer && oldContainer.innerHTML.trim().length > 0) {
      newContainer.innerHTML = oldContainer.innerHTML
    }
    
    const oldStyle = document.getElementById("abw-style")
    const newStyle = event.detail.newBody.querySelector("#abw-style")
    if (oldStyle && newStyle && oldStyle.innerHTML.trim().length > 0) {
      newStyle.innerHTML = oldStyle.innerHTML
    }
  }

  reinitialize() {
    if (typeof window.CreateABChatWidget !== "function") return
    if (!window.abWidgetConfig) return

    const container = document.getElementById("abw-btn-cont")
    
    if (container && container.innerHTML.trim().length > 0) {
      return
    }

    try {
      setTimeout(() => {
        if (typeof window.CreateABChatWidget === "function" && window.abWidgetConfig) {
          const freshContainer = document.getElementById("abw-btn-cont")
          if (freshContainer && freshContainer.innerHTML.trim().length === 0) {
            window.CreateABChatWidget(window.abWidgetConfig)
          }
        }
      }, 500)
    } catch (e) {
      console.warn("Widget re-initialization failed:", e)
    }
  }
}
