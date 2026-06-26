import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["latitude", "longitude", "status", "submitButton"]
  static values = {
    hotelLatitude: Number,
    hotelLongitude: Number,
    allowedRadius: { type: Number, default: 50 },
    refreshIcon: { type: String, default: "" },
    isMobile: { type: Boolean, default: false }
  }

  connect() {
    this.requestLocation()
  }

  requestLocation(event) {
    if (event) event.preventDefault()

    if (!navigator.geolocation) {
      this.setStatus("Geolocation is not supported by your browser.", "error")
      return
    }

    this.setStatus("Verifying your location...", "info")
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }

    navigator.geolocation.getCurrentPosition(
      (position) => this.success(position),
      (error) => this.error(error),
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
    )
  }

  success(position) {
    const lat = position.coords.latitude
    const lng = position.coords.longitude

    if (this.hasLatitudeTarget) this.latitudeTarget.value = lat
    if (this.hasLongitudeTarget) this.longitudeTarget.value = lng

    if (this.hotelLatitudeValue && this.hotelLongitudeValue) {
      const distance = this.calculateDistance(lat, lng, this.hotelLatitudeValue, this.hotelLongitudeValue)
      if (distance > this.allowedRadiusValue) {
        const distStr = distance >= 1000 ? `${(distance / 1000).toFixed(1)} km` : `${Math.round(distance)}m`
        const iconHtml = this.refreshIconValue || ""
        const messageHtml = `<span class="text-xs font-semibold leading-snug">You are ${distStr} away. Self-check-in is only allowed at the hotel (within ${this.allowedRadiusValue}m).</span>`
        const refreshBtn = `<button type='button' data-action='click->geolocation-check-in#reloadPage' class='inline-flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-black uppercase tracking-wider rounded-lg border border-red-300/40 bg-red-100/30 text-red-700 hover:bg-red-100/60 active:scale-[0.98] transition-all cursor-pointer flex-shrink-0'>${iconHtml}Refresh</button>`
        this.setStatus(`<div class="flex items-center justify-between w-full gap-4 text-left">${messageHtml}${refreshBtn}</div>`, "error")
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true
      } else {
        this.setStatus("✓ Location verified. Ready to check in.", "success")
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false
      }
    } else {
      this.setStatus("✓ Ready to check in.", "success")
      if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false
    }
  }

  error(error) {
    let msg = "Unable to retrieve location."

    if (error.code === error.PERMISSION_DENIED) {
      const iconHtml = this.refreshIconValue || ""
      const messageHtml = `<span class="text-xs font-semibold leading-snug">Location access denied. Please enable location services in your browser to check in.</span>`
      const instructionText = this.isMobileValue
        ? "Tap the lock icon next to the URL ➔ Permissionss ➔ Location ➔ Allow."
        : "Click the location icon in the URL ➔ Allow Location ➔ Done."
      const infoIcon = `
        <div class="relative inline-block group flex-shrink-0 cursor-pointer">
          <span class="inline-flex items-center justify-center w-4 h-4 rounded-full border border-red-400/80 text-[10px] font-black select-none text-red-700 bg-red-100/10 hover:bg-red-100/40 active:scale-95 transition-all focus:outline-none" tabindex="0">i</span>
          <div class='absolute left-1/2 bottom-full -translate-x-1/2 mb-2.5 w-56 hidden group-hover:block group-focus-within:block bg-slate-900 text-white text-[11px] rounded-xl p-3 shadow-xl z-50 border border-slate-800 text-center leading-normal pointer-events-none'>
            <div class='font-bold border-b border-slate-800/80 pb-1.5 mb-1.5 text-xs text-white'>Enable Location in Chrome:</div>
            <div class='text-slate-300'>${instructionText}</div>
            <div class='absolute top-full left-1/2 -translate-x-1/2 -mt-1 border-4 border-transparent border-t-slate-900'></div>
          </div>
        </div>
      `
      const refreshBtn = `<button type='button' data-action='click->geolocation-check-in#reloadPage' class='inline-flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-black uppercase tracking-wider rounded-lg border border-red-300/40 bg-red-100/30 text-red-700 hover:bg-red-100/60 active:scale-[0.98] transition-all cursor-pointer flex-shrink-0'>${iconHtml}Refresh</button>`
      this.setStatus(`<div class="flex items-center justify-between w-full gap-4 text-left"><div class="flex items-center gap-2">${messageHtml}${infoIcon}</div>${refreshBtn}</div>`, "error")
      if (this.hasSubmitButtonTarget) {
        this.submitButtonTarget.disabled = true
      }
      return
    } else if (error.code === error.POSITION_UNAVAILABLE) {
      msg = "Location information is unavailable. Please check your GPS signal."
    } else if (error.code === error.TIMEOUT) {
      msg = "Location request timed out. Please try again."
    }

    this.setStatus(msg, "error")
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
    }
  }

  reloadPage(event) {
    if (event) event.preventDefault()
    window.location.reload()
  }

  setStatus(message, type) {
    if (!this.hasStatusTarget) return

    this.statusTarget.innerHTML = message
    this.statusTarget.className = "text-xs font-semibold py-2.5 px-4 rounded-xl mt-2 block w-full text-center"

    if (type === "success") {
      this.statusTarget.classList.add("bg-green-50", "text-green-700", "border", "border-green-200")
    } else if (type === "error") {
      this.statusTarget.classList.add("bg-red-50", "text-red-700", "border", "border-red-200")
    } else {
      this.statusTarget.classList.add("bg-slate-50", "text-slate-700", "border", "border-slate-200/50")
    }
  }

  calculateDistance(lat1, lon1, lat2, lon2) {
    const rad = Math.PI / 180
    const R = 6371000 // Earth radius in meters
    const dLat = (lat2 - lat1) * rad
    const dLon = (lon2 - lon1) * rad
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
              Math.cos(lat1 * rad) * Math.cos(lat2 * rad) *
              Math.sin(dLon / 2) * Math.sin(dLon / 2)
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    return R * c
  }
}
