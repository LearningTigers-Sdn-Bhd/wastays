import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select"]
  static values = {
    url: String,
    roomTypeId: String,
    checkIn: String,
    checkOut: String,
    bookingId: String,
    currentRoom: String
  }

  connect() {
    this.loadOptions()
  }

  async loadOptions() {
    const select = this.hasSelectTarget ? this.selectTarget : this.element
    if (select.tagName !== "SELECT") return

    if (!this.urlValue || !this.roomTypeIdValue || !this.checkInValue || !this.checkOutValue) {
      select.innerHTML = '<option value="">Missing stay details...</option>'
      select.disabled = true
      return
    }

    const originalValue = this.currentRoomValue || select.value

    select.innerHTML = '<option value="">Checking availability...</option>'
    select.disabled = true

    try {
      const params = new URLSearchParams({
        room_type_id: this.roomTypeIdValue,
        check_in: this.checkInValue,
        check_out: this.checkOutValue,
        exclude_booking_id: this.bookingIdValue
      })

      const response = await fetch(`${this.urlValue}?${params}`)
      if (!response.ok) throw new Error("Failed to fetch available rooms")

      const data = await response.json()
      if (data.error) throw new Error(data.error)
      
      this.populateSelect(select, data.available_rooms || [], data.room_options || [], originalValue)
    } catch (error) {
      console.error("[RoomSelection] Load failed:", error)
      select.innerHTML = `<option value="">Error: ${error.message}</option>`
    } finally {
      select.disabled = false
    }
  }

  populateSelect(select, numbers, roomOptions, currentSelection) {
    select.innerHTML = ""
    
    const prompt = document.createElement("option")
    prompt.value = ""
    prompt.textContent = (numbers.length > 0 || (Array.isArray(roomOptions) && roomOptions.length > 0)) 
      ? "Select an available room" 
      : "No available rooms for these dates"
    select.appendChild(prompt)

    if (Array.isArray(roomOptions) && roomOptions.length > 0) {
      roomOptions.forEach(room => {
        const option = document.createElement("option")
        option.value = room.room_number
        option.textContent = room.label || room.room_number
        option.disabled = !room.selectable
        if (room.room_number?.toString() === (currentSelection || "").toString()) {
          option.selected = true
        }
        select.appendChild(option)
      })
    } else {
      numbers.forEach(num => {
        const option = document.createElement("option")
        option.value = num
        option.textContent = num
        if (num.toString() === (currentSelection || "").toString()) {
          option.selected = true
        }
        select.appendChild(option)
      })
    }
    
    // Add red border if no rooms available
    if (numbers.length === 0 && (!roomOptions || roomOptions.length === 0)) {
      select.classList.add("border-red-500")
    } else {
      select.classList.remove("border-red-500")
    }
  }
}
