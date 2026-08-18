import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["appliesTo", "targetField", "targetInput", "hotelField", "hotelInput", "roomTypeField", "roomTypeInput"]

  connect() {
    this.toggle()
  }

  toggle() {
    const selectedType = this.appliesToTarget.value

    if (this.hasTargetFieldTarget && this.hasTargetInputTarget) {
      const showTargetField = selectedType !== ""
      this.targetFieldTarget.classList.toggle("hidden", !showTargetField)
      this.targetInputTarget.disabled = !showTargetField
      if (!showTargetField) this.targetInputTarget.value = ""
    }

    if (this.hasHotelFieldTarget) {
      const isHotel = selectedType === "Hotel"
      this.hotelFieldTarget.classList.toggle("hidden", !isHotel)
      if (this.hasHotelInputTarget) {
        this.hotelInputTarget.disabled = !isHotel
        if (!isHotel) this.hotelInputTarget.value = ""
      }
    }

    if (this.hasRoomTypeFieldTarget) {
      const isRoomType = selectedType === "RoomType"
      this.roomTypeFieldTarget.classList.toggle("hidden", !isRoomType)
      if (this.hasRoomTypeInputTarget) {
        this.roomTypeInputTarget.disabled = !isRoomType
        if (!isRoomType) this.roomTypeInputTarget.value = ""
      }
    }
  }
}
