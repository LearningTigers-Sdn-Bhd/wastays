import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  connect() {
    console.log("ReservationBoardModalController connected")
    this.overlayRequestId = 0
    this.boundOpen = this.open.bind(this)
    this.boundOpenCheckIn = this.openCheckIn.bind(this)
    this.boundOpenCheckOut = this.openCheckOut.bind(this)
    this.boundOpenEditStay = this.openEditStay.bind(this)
    this.boundOpenNotes = this.openNotes.bind(this)
    this.boundOpenBookingSheet = this.openBookingSheet.bind(this)
    this.boundOpenExtendDuration = this.openExtendDuration.bind(this)
    this.boundCloseAll = this.closeAllOverlays.bind(this)

    window.addEventListener("reservation-board:open-modal", this.boundOpen)
    window.addEventListener("reservation-board:open-check-in", this.boundOpenCheckIn)
    window.addEventListener("reservation-board:open-check-out", this.boundOpenCheckOut)
    window.addEventListener("reservation-board:open-edit-stay", this.boundOpenEditStay)
    window.addEventListener("reservation-board:open-notes", this.boundOpenNotes)
    window.addEventListener("reservation-board:open-booking-sheet", this.boundOpenBookingSheet)
    window.addEventListener("reservation-board:open-extend-duration", this.boundOpenExtendDuration)
    window.addEventListener("reservation-board:close-all", this.boundCloseAll)
    
    // Listen for board reloads to close any open modals
    document.addEventListener("turbo:before-stream-render", (event) => {
      const isReloadAction = event.detail.newStream?.getAttribute("action") === "reload"
      if (isReloadAction) this.closeAllOverlays()
    })

    // Listen for Preline's own close events globally
    document.addEventListener("before-hide.hs.overlay", () => this.cleanupBodyAndBackdrops())
    document.addEventListener("after-hide.hs.overlay", () => {
      this.cleanupBodyAndBackdrops()
      this.clearActionFrames()
    })
  }

  disconnect() {
    window.removeEventListener("reservation-board:open-modal", this.boundOpen)
    window.removeEventListener("reservation-board:open-check-in", this.boundOpenCheckIn)
    window.removeEventListener("reservation-board:open-check-out", this.boundOpenCheckOut)
    window.removeEventListener("reservation-board:open-edit-stay", this.boundOpenEditStay)
    window.removeEventListener("reservation-board:open-notes", this.boundOpenNotes)
    window.removeEventListener("reservation-board:open-booking-sheet", this.boundOpenBookingSheet)
    window.removeEventListener("reservation-board:open-extend-duration", this.boundOpenExtendDuration)
    window.removeEventListener("reservation-board:close-all", this.boundCloseAll)
  }

  open(event) {
    const { url, frameId } = event.detail
    this.openOverlay("reservation-board-booking-sheet", frameId || "reservation_board_booking_sheet_content", url)
  }

  openCheckIn(event) {
    const { url, frameId } = event.detail
    this.openOverlay("reservation-board-check-in-overlay", frameId || "reservation_board_check_in_content", url)
  }

  openCheckOut(event) {
    const { url, frameId } = event.detail
    this.openOverlay("reservation-board-check-out-overlay", frameId || "reservation_board_check_out_content", url)
  }

  openEditStay(event) {
    const { url, frameId } = event.detail
    this.openOverlay("reservation-board-edit-stay-overlay", frameId || "reservation_board_edit_stay_content", url)
  }

  openNotes(event) {
    const { url, frameId } = event.detail
    this.openOverlay("reservation-board-notes-modal", frameId || "reservation_board_notes_content", url)
  }

  openBookingSheet(event) {
    const { url, frameId } = event.detail
    this.openOverlay("reservation-board-booking-sheet", frameId || "reservation_board_booking_sheet_content", url)
  }

  openExtendDuration() {
    this.openOverlay("reservation-board-extend-duration-overlay", null, null)
  }

  closeOnSuccess(event) {
    if (event.detail.success) this.closeAllOverlays()
  }

  async openOverlay(overlayId, frameId, url) {
    console.log(`Opening overlay: ${overlayId}`, { frameId, url })
    const overlay = document.getElementById(overlayId)
    if (!overlay) {
      console.warn(`Overlay element not found: ${overlayId}`)
      return
    }

    const requestId = ++this.overlayRequestId

    if (frameId && url) {
      const frame = document.getElementById(frameId)
      if (frame) {
        // Clear previous content and src to force a fresh load
        frame.removeAttribute("src")
        frame.innerHTML = `<div class="flex items-center justify-center py-20"><div class="size-8 animate-spin rounded-full border-4 border-slate-200 border-t-violet-600"></div></div>`
        
        // Use requestAnimationFrame to ensure the DOM is cleared before setting the new src
        requestAnimationFrame(() => {
          frame.src = url
          frame.reload() // Force Turbo to fetch even if URL is same
        })
      }
    }

    await this.ensurePrelineOverlayReady(overlay)
    if (requestId !== this.overlayRequestId) return

    // Re-initialize to ensure frame content hasn't broken bindings
    window.HSStaticMethods?.autoInit?.(["overlay"])

    this.openPrelineOverlay(overlay, overlayId)
  }

  close(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    this.closeAllOverlays()
  }

  async closeAllOverlays() {
    console.log("Closing all overlays via controller")
    this.overlayRequestId += 1
    
    this.element.querySelectorAll(".hs-overlay").forEach((overlay) => {
      this.closePrelineOverlay(overlay)
      overlay.classList.add("hidden")
      overlay.classList.remove("open")
    })

    this.cleanupBodyAndBackdrops()
    this.clearActionFrames()
  }

  cleanupBodyAndBackdrops() {
    console.log("Cleanup: Removing backdrops and unlocking body")
    
    // 1. Remove ALL Preline backdrops
    document.querySelectorAll(".hs-overlay-backdrop").forEach(backdrop => backdrop.remove())

    // 2. Force reset body and html styles/classes
    const targets = [document.body, document.documentElement]
    targets.forEach(el => {
      el.style.overflow = ""
      el.style.pointerEvents = "auto" // Explicitly set to auto first
      el.style.paddingRight = ""
      el.classList.remove("overflow-hidden")
      el.classList.remove("hs-overlay-open")
      el.removeAttribute("inert")
      
      // Reset back to empty string in next tick to allow CSS to take over
      setTimeout(() => { el.style.pointerEvents = "" }, 0)
    })

    // 3. Close any stray 'open' classes and reset opacity
    document.querySelectorAll(".hs-overlay.open").forEach(el => {
      el.classList.add("hidden")
      el.classList.remove("open")
      
      const content = el.querySelector("[class*='opacity-100']")
      if (content) {
        content.classList.add("opacity-0")
        content.classList.remove("opacity-100")
      }
    })

    // 4. Reset any elements that might have been marked inert by Preline
    document.querySelectorAll("[inert]").forEach(el => el.removeAttribute("inert"))

    // 5. Force focus back to body to break any focus traps
    document.body.focus()
    if (document.activeElement instanceof HTMLElement) {
      document.activeElement.blur()
    }
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
    
    // If instance is null, try to manually initialize it
    if (!instance && window.HSOverlay) {
      console.log(`Manually initializing Preline for: ${overlayId}`)
      new window.HSOverlay(overlay)
      instance = window.HSOverlay.getInstance(overlay, true)
    }

    console.log("Preline instance found for open:", instance)

    if (instance?.open) {
      console.log("Using instance.open()")
      instance.open()
    } else if (window.HSOverlay?.open) {
      console.log("Using window.HSOverlay.open()")
      window.HSOverlay.open(overlay)
    }

    // Diagnostic & Fallback: Check if classes changed
    setTimeout(() => {
      if (overlay.classList.contains("hidden") || !overlay.classList.contains("open")) {
        console.warn("Preline failed to show overlay, forcing visibility")
        overlay.classList.remove("hidden")
        overlay.classList.add("open")
        
        // Target the inner container that uses Preline's transition classes
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
    console.log("Preline instance found for close:", instance)

    if (instance?.close) {
      console.log("Using instance.close()")
      instance.close()
    } else if (instance?.element?.close) {
      console.log("Using instance.element.close()")
      instance.element.close()
    } else if (window.HSOverlay?.close) {
      console.log("Using window.HSOverlay.close()")
      window.HSOverlay.close(overlay)
    }
  }

  clearActionFrames() {
    requestAnimationFrame(() => {
      this.element.querySelectorAll("turbo-frame").forEach((frame) => {
        frame.removeAttribute("src")
        frame.innerHTML = ""
      })
    })
  }
}
