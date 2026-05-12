import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "roomDisplay", "roomNumber", "roomTypeId", "startDate", "endDate", "blockType", "reason", "form", "submit", "title"]

  open(event) {
    const { date, roomNumber, roomTypeId, roomTypeName } = event.params
    
    // Reset form to create mode
    this.titleTarget.textContent = "Schedule Maintenance"
    this.submitTarget.value = "Schedule Block"
    this.formTarget.action = this.formTarget.dataset.createUrl
    this.formTarget.querySelector('input[name="_method"]')?.remove()
    
    // Set field values
    this.roomNumberTarget.value = roomNumber
    this.roomTypeIdTarget.value = roomTypeId
    this.startDateTarget.value = date
    this.endDateTarget.value = date // Default to single day
    this.blockTypeTarget.value = ""
    this.reasonTarget.value = ""
    
    // Update display
    this.roomDisplayTarget.textContent = `${roomTypeName} Room ${roomNumber}`
    
    // Open dialog
    this.dialogTarget.showModal()
  }

  edit(event) {
    const { id, roomNumber, roomTypeId, roomTypeName, startDate, endDate, blockType, reason, updateUrl } = event.params
    
    // Set form to edit mode
    this.titleTarget.textContent = "Edit Maintenance Block"
    this.submitTarget.value = "Update Block"
    this.formTarget.action = updateUrl
    
    // Add _method hidden field for PATCH
    if (!this.formTarget.querySelector('input[name="_method"]')) {
      const methodField = document.createElement("input")
      methodField.type = "hidden"
      methodField.name = "_method"
      methodField.value = "patch"
      this.formTarget.appendChild(methodField)
    }
    
    // Set field values
    this.roomNumberTarget.value = roomNumber
    this.roomTypeIdTarget.value = roomTypeId
    this.startDateTarget.value = startDate
    this.endDateTarget.value = endDate
    this.blockTypeTarget.value = blockType
    this.reasonTarget.value = reason
    
    // Update display
    this.roomDisplayTarget.textContent = `${roomTypeName} Room ${roomNumber}`
    
    // Open dialog
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
