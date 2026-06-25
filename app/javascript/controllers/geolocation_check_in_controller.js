import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["latitude", "longitude", "status", "submitButton"]
  static values = {
    hotelLatitude: Number,
    hotelLongitude: Number,
    allowedRadius: { type: Number, default: 100 }
  }

  connect() {
    this.requestLocation()
  }

  requestLocation() {
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
        this.setStatus(`You are ${distStr} away. Self-check-in is only allowed at the hotel (within ${this.allowedRadiusValue}m).`, "error")
        if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true
      } else {
        const distStr = distance >= 1000 ? `${(distance / 1000).toFixed(1)} km` : `${Math.round(distance)}m`
        this.setStatus(`✓ Location verified (${distStr} from property). Ready to check in.`, "success")
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
      msg = "Location access denied. Please enable location services in your browser to check in."
    } else if (error.code === error.POSITION_UNAVAILABLE) {
      msg = "Location information is unavailable. Please check your GPS signal."
    } else if (error.code === error.TIMEOUT) {
      msg = "Location request timed out. Please try again."
    }
    this.setStatus(msg, "error")
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true
  }

  setStatus(message, type) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
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
