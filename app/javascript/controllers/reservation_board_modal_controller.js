import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    this.overlayRequestId = 0
    this.boundOpenExtendDuration = this.openExtendDuration.bind(this)
    this.boundCloseAll = this.closeAllOverlays.bind(this)

    window.addEventListener("reservation-board:open-extend-duration", this.boundOpenExtendDuration)
    window.addEventListener("reservation-board:close-all", this.boundCloseAll)
  }

  disconnect() {
    window.removeEventListener("reservation-board:open-extend-duration", this.boundOpenExtendDuration)
    window.removeEventListener("reservation-board:close-all", this.boundCloseAll)
  }

  openExtendDuration() {
    this.openOverlay("reservation-board-extend-duration-overlay", null, null)
  }

  async closeAllOverlays() {
    this.overlayRequestId += 1

    this.element.querySelectorAll(".hs-overlay").forEach((overlay) => {
      this.closePrelineOverlay(overlay)
      overlay.classList.add("hidden")
      overlay.classList.remove("open")
    })

    this.cleanupBodyAndBackdrops()
  }

  cleanupBodyAndBackdrops() {
    document.querySelectorAll(".hs-overlay-backdrop").forEach(backdrop => backdrop.remove())

    const targets = [document.body, document.documentElement]
    targets.forEach(el => {
      el.style.overflow = ""
      el.style.pointerEvents = "auto"
      el.style.paddingRight = ""
      el.classList.remove("overflow-hidden")
      el.classList.remove("hs-overlay-open")
      el.removeAttribute("inert")
      setTimeout(() => { el.style.pointerEvents = "" }, 0)
    })

    document.querySelectorAll(".hs-overlay.open").forEach(el => {
      el.classList.add("hidden")
      el.classList.remove("open")
      const content = el.querySelector("[class*='opacity-100']")
      if (content) {
        content.classList.add("opacity-0")
        content.classList.remove("opacity-100")
      }
    })

    document.querySelectorAll("[inert]").forEach(el => el.removeAttribute("inert"))
    document.body.focus()
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur()
    }
  }

  async openOverlay(overlayId, frameId, url) {
    const overlay = document.getElementById(overlayId)
    if (!overlay) return

    const requestId = ++this.overlayRequestId

    if (frameId && url) {
      const frame = document.getElementById(frameId)
      if (frame) {
        frame.removeAttribute("src")
        frame.innerHTML = `<div class="flex items-center justify-center py-20"><div class="size-8 animate-spin rounded-full border-4 border-slate-200 border-t-violet-600"></div></div>`
        requestAnimationFrame(() => {
          frame.src = url
          frame.reload()
        })
      }
    }

    await this.ensurePrelineOverlayReady(overlay)
    if (requestId !== this.overlayRequestId) return

    window.HSStaticMethods?.autoInit?.(["overlay"])
    this.openPrelineOverlay(overlay, overlayId)
  }

  async ensurePrelineOverlayReady(overlay = null) {
    if (!window.HSOverlay) {
      try {
        await import("preline")
      } catch (error) {
        console.warn("Preline overlay import failed", error)
      }
    }
    if (overlay) return window.HSOverlay?.getInstance?.(overlay, true)
  }

  openPrelineOverlay(overlay, overlayId) {
    let instance = window.HSOverlay?.getInstance?.(overlay, true)

    if (!instance && window.HSOverlay) {
      new window.HSOverlay(overlay)
      instance = window.HSOverlay.getInstance(overlay, true)
    }

    if (instance?.open) {
      instance.open()
    } else if (window.HSOverlay?.open) {
      window.HSOverlay.open(overlay)
    }

    setTimeout(() => {
      if (overlay.classList.contains("hidden") || !overlay.classList.contains("open")) {
        overlay.classList.remove("hidden")
        overlay.classList.add("open")
        const content = overlay.querySelector(".hs-overlay-open\\:opacity-100")
        if (content) {
          content.classList.remove("opacity-0")
          content.classList.add("opacity-100")
        }
      }
    }, 200)
  }

  closePrelineOverlay(overlay) {
    const instance = window.HSOverlay?.getInstance?.(overlay, true)

    if (instance?.close) {
      instance.close()
    } else if (instance?.element?.close) {
      instance.element.close()
    } else if (window.HSOverlay?.close) {
      window.HSOverlay.close(overlay)
    }
  }
}
