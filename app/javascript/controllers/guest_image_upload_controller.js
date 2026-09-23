import { Controller } from "@hotwired/stimulus"

// GuestUI::ImageUpload. Opens the file input, which a phone answers with its
// own menu (photo library, camera, files), and shows the photo once chosen.
export default class extends Controller {
  static targets = ["input", "preview", "status"]

  disconnect() {
    this.revoke()
  }

  choose(event) {
    event.preventDefault()
    if (this.inputTarget.disabled) return
    this.inputTarget.click()
  }

  changed() {
    const file = this.inputTarget.files[0]

    // Some phones clear the input when the guest cancels the menu. Keep the
    // photo they already chose rather than losing it to a cancel.
    if (!file) {
      if (this.lastFile) this.restore()
      return
    }

    this.lastFile = file
    this.revoke()
    this.objectUrl = URL.createObjectURL(file)
    this.previewTarget.src = this.objectUrl
    this.element.dataset.state = "filled"
    this.inputTarget.required = false
    this.statusTarget.textContent = `Photo added: ${this.labelText}.`
  }

  restore() {
    const transfer = new DataTransfer()
    transfer.items.add(this.lastFile)
    this.inputTarget.files = transfer.files
  }

  revoke() {
    if (this.objectUrl) URL.revokeObjectURL(this.objectUrl)
    this.objectUrl = null
  }

  get labelText() {
    return this.element.querySelector("[data-upload-label]")?.textContent.trim() || "photo"
  }
}
