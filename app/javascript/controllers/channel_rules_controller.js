import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "dialog", "typeSelect", "valueGroup", "channelCheckbox", "roomTypeCheckbox" ]

  connect() {
    this.toggleValueField()
  }

  open(event) {
    if (event) event.preventDefault()
    this.dialogTarget.showModal()
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
  }

  toggleValueField() {
    if (!this.hasTypeSelectTarget) return
    const type = this.typeSelectTarget.value
    const needsValue = type === "max_availability" || type === "availability_offset"
    if (this.hasValueGroupTarget) {
      this.valueGroupTarget.classList.toggle("hidden", !needsValue)
    }
  }

  selectAllChannels(event) {
    const checked = event.currentTarget.checked
    this.channelCheckboxTargets.forEach(cb => {
      cb.checked = checked
    })
  }

  selectAllRoomTypes(event) {
    const checked = event.currentTarget.checked
    this.roomTypeCheckboxTargets.forEach(cb => {
      cb.checked = checked
    })
  }
}
