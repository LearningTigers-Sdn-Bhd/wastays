import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input", "surface", "error", "selection", "attachments", "template", "count",
    "emptyState", "imageState", "previewImage", "pendingRemoval", "removeInput"
  ]
  static values = {
    accept: String,
    multiple: Boolean,
    maxFiles: Number,
    maxSize: Number,
    existingCount: Number,
    preview: { type: String, default: "auto" },
    presentation: { type: String, default: "files" }
  }

  connect() {
    this.selectedFiles = Array.from(this.inputTarget.files || [])
    this.previewUrls = new Map()
    this.dragDepth = 0
    this.removalPending = this.hasRemoveInputTarget && this.removeInputTarget.value === "1"
    this.existingImageUrl = this.hasPreviewImageTarget ? this.previewImageTarget.dataset.existingSrc : ""
    this.existingImageAlt = this.hasPreviewImageTarget ? this.previewImageTarget.dataset.existingAlt : "Current image"
    this.render()
  }

  disconnect() {
    this.revokePreviewUrls()
  }

  select(event) {
    if (this.disabled) return

    const incoming = Array.from(event.currentTarget.files || [])
    this.acceptFiles(incoming, { replace: !this.multipleValue })
  }

  browse(event) {
    event.preventDefault()
    if (this.disabled) return

    this.inputTarget.click()
  }

  dragenter(event) {
    if (!this.isFileDrag(event)) return

    event.preventDefault()
    if (this.disabled) return
    this.dragDepth += 1
    this.surfaceTarget.dataset.state = "dragging"
  }

  dragover(event) {
    if (!this.isFileDrag(event)) return

    event.preventDefault()
    if (this.disabled) return
    event.dataTransfer.dropEffect = "copy"
    this.surfaceTarget.dataset.state = "dragging"
  }

  dragleave(event) {
    if (!this.isFileDrag(event)) return

    event.preventDefault()
    this.dragDepth = Math.max(0, this.dragDepth - 1)
    if (this.dragDepth === 0) this.restoreSurfaceState()
  }

  drop(event) {
    if (!this.isFileDrag(event)) return

    event.preventDefault()
    if (this.disabled) return
    this.dragDepth = 0
    this.restoreSurfaceState()
    this.acceptFiles(Array.from(event.dataTransfer.files || []), { replace: !this.multipleValue })
  }

  remove(event) {
    event.preventDefault()
    const key = event.currentTarget.dataset.fileKey
    this.selectedFiles = this.selectedFiles.filter((file) => this.fileKey(file) !== key)
    this.syncInput()
    this.clearError()
    this.render()
  }

  removeImage(event) {
    event.preventDefault()
    if (this.disabled) return

    this.selectedFiles = []
    this.syncInput()
    this.setRemovalPending(this.existingImageUrl !== "")
    this.clearError()
    this.render()
  }

  undoRemoveImage(event) {
    event.preventDefault()
    if (this.disabled) return

    this.setRemovalPending(false)
    this.clearError()
    this.render()
  }

  clear(event) {
    event?.preventDefault()
    this.selectedFiles = []
    this.syncInput()
    this.clearError()
    this.render()
  }

  reset(event) {
    if (!event.target.contains(this.element)) return

    requestAnimationFrame(() => {
      this.selectedFiles = Array.from(this.inputTarget.files || [])
      this.setRemovalPending(false, { notify: false })
      this.clearError()
      this.render()
    })
  }

  acceptFiles(files, { replace }) {
    this.clearError()

    const errors = []
    const base = replace ? [] : [...this.selectedFiles]
    const knownKeys = new Set(base.map((file) => this.fileKey(file)))
    const valid = []

    files.forEach((file) => {
      const key = this.fileKey(file)
      if (knownKeys.has(key)) return

      if (!this.matchesAccept(file)) {
        errors.push(`${file.name} is not an accepted file type.`)
        return
      }

      if (this.hasMaxSizeValue && this.maxSizeValue > 0 && file.size > this.maxSizeValue) {
        errors.push(`${file.name} is larger than ${this.formatBytes(this.maxSizeValue)}.`)
        return
      }

      knownKeys.add(key)
      valid.push(file)
    })

    const remaining = this.remainingSlots(base.length)
    if (valid.length > remaining) {
      errors.push(`Only ${remaining} more ${remaining === 1 ? "file" : "files"} can be selected.`)
      valid.splice(remaining)
    }

    this.selectedFiles = this.multipleValue ? [...base, ...valid] : valid.slice(0, 1)
    if (this.selectedFiles.length > 0) this.setRemovalPending(false, { notify: false })
    this.syncInput()
    this.render()
    if (errors.length > 0) this.showError(errors.join(" "))
  }

  render() {
    if (this.presentationValue === "single_image") {
      this.renderSingleImage()
      return
    }

    this.revokePreviewUrls()
    this.attachmentsTarget.replaceChildren()

    this.selectedFiles.forEach((file) => {
      const fragment = this.templateTarget.content.cloneNode(true)
      const attachment = fragment.querySelector(".panel-attachment")
      const media = fragment.querySelector(".panel-attachment__media")
      const icon = fragment.querySelector(".panel-dropzone__file-icon")
      const image = fragment.querySelector(".panel-dropzone__thumbnail")
      const title = fragment.querySelector(".panel-attachment__title")
      const description = fragment.querySelector(".panel-attachment__description")
      const remove = fragment.querySelector("[data-action~='panels-ui--dropzone#remove']")
      const key = this.fileKey(file)

      attachment.dataset.fileKey = key
      title.textContent = file.name

      description.textContent = `Ready to upload · ${this.fileTypeLabel(file)} · ${this.formatBytes(file.size)}`

      remove.dataset.fileKey = key
      remove.setAttribute("aria-label", `Remove ${file.name}`)

      if (this.shouldPreviewImage(file)) {
        const objectUrl = URL.createObjectURL(file)
        this.previewUrls.set(key, objectUrl)
        media.dataset.variant = "image"
        icon.hidden = true
        image.hidden = false
        image.src = objectUrl
        image.alt = `Preview of ${file.name}`
      }

      this.attachmentsTarget.appendChild(fragment)
    })

    const count = this.selectedFiles.length
    this.selectionTarget.hidden = count === 0
    this.countTarget.textContent = `${count} selected ${count === 1 ? "file" : "files"}`
  }

  renderSingleImage() {
    this.revokePreviewUrls()

    const file = this.selectedFiles[0]
    let source = ""
    let alt = this.existingImageAlt

    if (file && this.shouldPreviewImage(file)) {
      source = URL.createObjectURL(file)
      this.previewUrls.set(this.fileKey(file), source)
      alt = `Preview of ${file.name}`
    } else if (!this.removalPending) {
      source = this.existingImageUrl
    }

    const hasImage = source !== ""
    this.imageStateTarget.hidden = !hasImage
    this.emptyStateTarget.hidden = hasImage
    this.pendingRemovalTarget.hidden = !this.removalPending
    this.previewImageTarget.hidden = !hasImage
    this.previewImageTarget.src = source
    this.previewImageTarget.alt = alt
  }

  setRemovalPending(value, { notify = true } = {}) {
    this.removalPending = value
    if (!this.hasRemoveInputTarget) return

    this.removeInputTarget.value = value ? "1" : "0"
    if (notify) this.removeInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
  }

  syncInput() {
    const transfer = new DataTransfer()
    this.selectedFiles.forEach((file) => transfer.items.add(file))
    this.inputTarget.files = transfer.files
  }

  matchesAccept(file) {
    if (!this.hasAcceptValue || this.acceptValue.trim() === "") return true

    const filename = file.name.toLowerCase()
    const type = file.type.toLowerCase()

    return this.acceptValue.split(",").some((entry) => {
      const rule = entry.trim().toLowerCase()
      if (rule === "") return false
      if (rule.startsWith(".")) return filename.endsWith(rule)
      if (rule.endsWith("/*")) return type.startsWith(rule.slice(0, -1))
      return type === rule
    })
  }

  remainingSlots(selectedCount) {
    const limit = this.multipleValue
      ? (this.hasMaxFilesValue && this.maxFilesValue > 0 ? this.maxFilesValue : Number.POSITIVE_INFINITY)
      : 1
    return Math.max(0, limit - this.existingCountValue - selectedCount)
  }

  shouldPreviewImage(file) {
    return this.previewValue === "image" || (this.previewValue === "auto" && file.type.startsWith("image/"))
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
    this.surfaceTarget.dataset.state = "invalid"
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.hidden = true
    this.restoreSurfaceState()
  }

  restoreSurfaceState() {
    this.surfaceTarget.dataset.state = this.element.dataset.invalid === "true" ? "invalid" : "idle"
  }

  revokePreviewUrls() {
    if (!this.previewUrls) return

    this.previewUrls.forEach((url) => URL.revokeObjectURL(url))
    this.previewUrls.clear()
  }

  fileKey(file) {
    return `${file.name}:${file.size}:${file.lastModified}`
  }

  fileTypeLabel(file) {
    const extension = file.name.includes(".") ? file.name.split(".").pop().toUpperCase() : "File"
    return extension || file.type || "File"
  }

  formatBytes(bytes) {
    if (bytes === 0) return "0 Bytes"

    const units = ["Bytes", "KB", "MB", "GB"]
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
    const value = bytes / (1024 ** index)
    return `${value.toFixed(index === 0 ? 0 : 1)} ${units[index]}`
  }

  isFileDrag(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  get disabled() {
    return this.inputTarget.disabled
  }
}
