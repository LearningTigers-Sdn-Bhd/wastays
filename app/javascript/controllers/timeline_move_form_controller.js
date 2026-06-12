import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["roomType", "roomNumber"]
  static values = { roomNumbers: Object }

  updateRoomNumbers() {
    const selectedRoomTypeId = this.roomTypeTarget.value
    const roomNumbers = this.roomNumbersValue[selectedRoomTypeId] || []

    this.roomNumberTarget.replaceChildren(
      ...roomNumbers.map((roomNumber) => new Option(roomNumber, roomNumber))
    )
  }
}
