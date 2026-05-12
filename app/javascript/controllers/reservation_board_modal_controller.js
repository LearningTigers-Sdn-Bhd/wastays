import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    const { url } = event.detail
    const frame = this.dialogTarget.querySelector("turbo-frame#reservation_board_modal_content")
    
    if (frame) {
      frame.src = url
      this.dialogTarget.showModal()
    }
  }

  close() {
    this.dialogTarget.close()
  }
}
