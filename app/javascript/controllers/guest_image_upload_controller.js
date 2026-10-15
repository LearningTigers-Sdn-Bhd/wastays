import { Controller } from "@hotwired/stimulus"

// GuestUI::ImageUpload. On a touch screen the button opens a sheet with Take
// a photo and Choose a photo or file; with a mouse it opens the file dialog.
// Shows the photo once chosen.
export default class extends Controller {
  static targets = ["input", "preview", "status"]

  disconnect() {
    this.revoke()
  }

  choose(event) {
    event.preventDefault()
    if (this.inputTarget.disabled) return

    if (this.touchScreen && this.sheet) {
      this.sheet.open()
    } else {
      this.openPicker(false)
    }
  }

  takePhoto(event) {
    event.preventDefault()
    this.openPicker(true)
  }

  choosePhoto(event) {
    event.preventDefault()
    this.openPicker(false)
  }

  // The dialog closes at once, not after its slide: while a modal dialog is
  // open the rest of the page is inert, and the input has to be clicked in
  // the same tap for the phone to open its camera or picker.
  openPicker(camera) {
    const dialog = this.sheet?.dialogTarget
    if (dialog?.open) dialog.close()

    if (camera) {
      this.inputTarget.setAttribute("capture", "environment")
    } else {
      this.inputTarget.removeAttribute("capture")
    }
    this.inputTarget.click()
  }

  changed() {
    const file = this.inputTarget.files[0]

    // Some phones clear the input when the guest cancels the picker. Keep the
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

  get sheet() {
    return this.application.getControllerForElementAndIdentifier(this.element, "concierge-modal")
  }

  get touchScreen() {
    return window.matchMedia("(pointer: coarse)").matches
  }

  get labelText() {
    return this.element.querySelector("[data-upload-label]")?.textContent.trim() || "photo"
  }
}
