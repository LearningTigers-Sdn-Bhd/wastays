import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkIn", "checkOut", "roomType", "guestCountry", "ratePlanSelect", "restrictionCheckbox", "totalInput", "displayTotal", "roomNumberSelect", "roomNumberContainer", "paymentAmountInput", "rateOverrideFlag"]
  static values = { availabilityUrl: String, rateOptionsUrl: String, priceUrl: String, bookingId: String, excludeBookingId: String }

  connect() {
    // Trigger initial calculation and room numbers load
    if (this.roomTypeTarget.value && this.checkInTarget.value && this.checkOutTarget.value) {
      this.calculate()
    }
  }

  async loadRateOptions() {
    const roomTypeId = this.roomTypeTarget.value
    const checkIn = this.checkInTarget.value
    const checkOut = this.checkOutTarget.value

    if (!this.hasRatePlanSelectTarget) return

    if (!roomTypeId || !checkIn || !checkOut || !this.hasRateOptionsUrlValue) {
      this.populateRateOptions([], "Select room category and dates first")
      return
    }

    const currentSelection = this.ratePlanSelectTarget.value
    this.populateRateOptions([], "Loading rates...")
    this.ratePlanSelectTarget.disabled = true

    try {
      const params = new URLSearchParams({
        room_type_id: roomTypeId,
        check_in: checkIn,
        check_out: checkOut
      })

      this.restrictionCheckboxTargets.forEach((checkbox) => {
        params.set(checkbox.name.replace(/^booking\[|\]$/g, ""), checkbox.checked ? "1" : "0")
      })

      const response = await fetch(`${this.rateOptionsUrlValue}?${params}`)
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`)

      const data = await response.json()
      this.populateRateOptions(data.rate_options || [], "No rate options available", currentSelection)
    } catch (error) {
      console.error("Rate options load failed:", error)
      this.populateRateOptions([], `Error: ${error.message}`)
    } finally {
      this.ratePlanSelectTarget.disabled = false
    }
  }

  populateRateOptions(options, promptText, currentSelection = "") {
    this.ratePlanSelectTarget.innerHTML = ""

    const prompt = document.createElement("option")
    prompt.value = ""
    prompt.textContent = options.length > 0 ? "Select a rate" : promptText
    this.ratePlanSelectTarget.appendChild(prompt)

    options.forEach((rateOption) => {
      const option = document.createElement("option")
      option.value = rateOption.id || ""
      option.textContent = `${rateOption.name} - ${rateOption.currency} ${parseFloat(rateOption.total_amount || 0).toFixed(2)}`
      if ((rateOption.id || "").toString() === (currentSelection || "").toString()) option.selected = true
      this.ratePlanSelectTarget.appendChild(option)
    })
  }

  async updateRoomNumbers() {
    const roomTypeId = this.roomTypeTarget.value
    const checkIn = this.checkInTarget.value
    const checkOut = this.checkOutTarget.value
    
    if (!roomTypeId || !checkIn || !checkOut) {
      this.roomNumberSelectTarget.innerHTML = '<option value="">Select room category and dates first</option>'
      this.roomNumberSelectTarget.disabled = true
      return
    }

    // Update the room-lock controller's room type if it exists in the same container
    if (this.hasRoomNumberContainerTarget) {
      const lockController = this.application.getControllerForElementAndIdentifier(this.element, "room-lock")
      if (lockController) {
        lockController.roomTypeIdValue = roomTypeId
      }
    }

    this.roomNumberSelectTarget.required = true
    
    const currentSelection = this.roomNumberSelectTarget.value
    this.roomNumberSelectTarget.innerHTML = '<option value="">Checking availability...</option>'
    this.roomNumberSelectTarget.disabled = true

    try {
      if (!this.hasAvailabilityUrlValue) return
      
      const bookingId = this.excludeBookingIdValue || this.bookingIdValue || ""
      const url = `${this.availabilityUrlValue}?room_type_id=${roomTypeId}&check_in=${checkIn}&check_out=${checkOut}&exclude_booking_id=${bookingId}`
      
      const response = await fetch(url)
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`)
      
      const data = await response.json()
      if (data.error) throw new Error(data.error)
      this.populateDropdown(data.available_rooms || [], data.room_options || [], currentSelection)
    } catch (error) {
      console.error("Availability check failed:", error)
      this.roomNumberSelectTarget.innerHTML = `<option value="">Error: ${error.message}</option>`
    } finally {
      this.roomNumberSelectTarget.disabled = false
    }
  }

  populateDropdown(numbers, roomOptions, currentSelection) {
    this.roomNumberSelectTarget.innerHTML = ""
    
    const prompt = document.createElement("option")
    prompt.value = ""
    prompt.textContent = numbers.length > 0 ? "Select an available room" : "No ready rooms available for these dates"
    this.roomNumberSelectTarget.appendChild(prompt)

    if (Array.isArray(roomOptions) && roomOptions.length > 0) {
      roomOptions.forEach(room => {
        const option = document.createElement("option")
        option.value = room.room_number
        option.textContent = room.label || room.room_number
        option.disabled = !room.selectable
        if (room.room_number?.toString() === (currentSelection || "").toString()) option.selected = true
        this.roomNumberSelectTarget.appendChild(option)
      })
    } else {
      numbers.forEach(num => {
        const option = document.createElement("option")
        option.value = num
        option.textContent = num
        if (num.toString() === (currentSelection || "").toString()) option.selected = true
        this.roomNumberSelectTarget.appendChild(option)
      })
    }

    if (numbers.length === 0) {
      this.roomNumberSelectTarget.classList.add("border-red-500")
    } else {
      this.roomNumberSelectTarget.classList.remove("border-red-500")
    }
  }

  // Backward compatibility helper if availability API returns only strings
  populateDropdownLegacy(numbers, currentSelection) {
    this.roomNumberSelectTarget.innerHTML = ""

    const prompt = document.createElement("option")
    prompt.value = ""
    prompt.textContent = numbers.length > 0 ? "Select an available room" : "No ready rooms available for these dates"
    this.roomNumberSelectTarget.appendChild(prompt)

    numbers.forEach((num) => {
      const option = document.createElement("option")
      option.value = num
      option.textContent = num
      if (num.toString() === (currentSelection || "").toString()) option.selected = true
      this.roomNumberSelectTarget.appendChild(option)
    })
    
    this.roomNumberSelectTarget.classList.toggle("border-red-500", numbers.length === 0)
  }

  async calculate() {
    const checkIn = this.checkInTarget.value
    const checkOut = this.checkOutTarget.value
    const roomTypeId = this.roomTypeTarget.value

    if (!checkIn || !checkOut || !roomTypeId) {
      if (this.hasDisplayTotalTarget) this.updateDisplay(0)
      return
    }

    // Crucial: Always check availability when dates/room type change
    await this.updateRoomNumbers()
    await this.loadRateOptions()

    if (!this.hasPriceUrlValue) return

    // Skip price calculation if manual override is active
    if (this.hasRateOverrideFlagTarget && this.rateOverrideFlagTarget.value === "1") {
      return
    }

    try {
      this.displayTotalTarget.textContent = "Calculating..."
      const params = new URLSearchParams({
        room_type_id: roomTypeId,
        check_in: checkIn,
        check_out: checkOut
      })
      if (this.hasRatePlanSelectTarget && this.ratePlanSelectTarget.value) {
        params.set("rate_plan_id", this.ratePlanSelectTarget.value)
      }
      if (this.hasGuestCountryTarget && this.guestCountryTarget.value) {
        params.set("guest_country", this.guestCountryTarget.value)
      }

      const url = `${this.priceUrlValue}?${params}`
      const response = await fetch(url)
      const data = await response.json()
      this.updateDisplay(parseFloat(data.total_amount || 0))
    } catch (error) {
      console.error("Price calculation failed:", error)
      this.updateDisplay(0)
    }
  }

  updateDisplay(amount) {
    if (!this.hasDisplayTotalTarget || !this.hasTotalInputTarget) return
    const formatted = amount.toFixed(2)
    this.displayTotalTarget.textContent = formatted
    this.totalInputTarget.value = formatted
    
    // Also update the manual payment amount field if it exists
    if (this.hasPaymentAmountInputTarget) {
      this.paymentAmountInputTarget.value = formatted
    }
  }

  // Called when user manually edits the total input
  setOverride() {
    if (this.hasRateOverrideFlagTarget) {
      this.rateOverrideFlagTarget.value = "1"
    }
  }

  clearOverride() {
    if (this.hasRateOverrideFlagTarget) {
      this.rateOverrideFlagTarget.value = ""
    }
    this.calculate()
  }
}
