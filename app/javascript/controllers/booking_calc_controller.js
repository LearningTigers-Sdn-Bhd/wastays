import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkIn", "checkOut", "roomType", "totalInput", "displayTotal", "roomNumberSelect", "roomNumberContainer"]
  static values = { availabilityUrl: String, priceUrl: String, bookingId: String }

  connect() {
    // Trigger initial calculation and room numbers load
    if (this.roomTypeTarget.value && this.checkInTarget.value && this.checkOutTarget.value) {
      this.calculate()
    }
  }

  async updateRoomNumbers() {
    const roomTypeId = this.roomTypeTarget.value
    const checkIn = this.checkInTarget.value
    const checkOut = this.checkOutTarget.value
    
    if (!roomTypeId || !checkIn || !checkOut) {
      if (this.hasRoomNumberContainerTarget) this.roomNumberContainerTarget.classList.add("hidden")
      return
    }

    // Show container and loading state
    if (this.hasRoomNumberContainerTarget) this.roomNumberContainerTarget.classList.remove("hidden")
    this.roomNumberSelectTarget.required = true
    
    const currentSelection = this.roomNumberSelectTarget.value
    this.roomNumberSelectTarget.innerHTML = '<option value="">Checking availability...</option>'
    this.roomNumberSelectTarget.disabled = true

    try {
      if (!this.hasAvailabilityUrlValue) return
      
      const bookingId = this.bookingIdValue || ""
      const url = `${this.availabilityUrlValue}?room_type_id=${roomTypeId}&check_in=${checkIn}&check_out=${checkOut}&exclude_booking_id=${bookingId}`
      
      const response = await fetch(url)
      if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`)
      
      const data = await response.json()
      if (data.error) throw new Error(data.error)
      this.populateDropdown(data.available_rooms, currentSelection)
    } catch (error) {
      console.error("Availability check failed:", error)
      this.roomNumberSelectTarget.innerHTML = `<option value="">Error: ${error.message}</option>`
    } finally {
      this.roomNumberSelectTarget.disabled = false
    }
  }

  populateDropdown(numbers, currentSelection) {
    this.roomNumberSelectTarget.innerHTML = ""
    
    const prompt = document.createElement("option")
    prompt.value = ""
    prompt.textContent = numbers.length > 0 ? "Select an available room" : "No rooms available for these dates"
    this.roomNumberSelectTarget.appendChild(prompt)

    numbers.forEach(num => {
      const option = document.createElement("option")
      option.value = num
      option.textContent = num
      if (num.toString() === (currentSelection || "").toString()) option.selected = true
      this.roomNumberSelectTarget.appendChild(option)
    })
    
    if (numbers.length === 0) {
      this.roomNumberSelectTarget.classList.add("border-red-500")
    } else {
      this.roomNumberSelectTarget.classList.remove("border-red-500")
    }
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
    this.updateRoomNumbers()

    if (!this.hasPriceUrlValue) return

    try {
      this.displayTotalTarget.textContent = "Calculating..."
      const url = `${this.priceUrlValue}?room_type_id=${roomTypeId}&check_in=${checkIn}&check_out=${checkOut}`
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
  }
}
