import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "input",
    "uploadForm",
    "queueList",
    "emptyState",
    "counterText",
    "warning",
    "error",
    "confirmButton",
    "discardButton",
    "uploadTemplate",
    "errorTemplate",
    "queuedTemplate"
  ]

  static values = {
    uploadUrl: String,
    clearUrl: String,
    commitUrl: String,
    removeUrlTemplate: String,
    existingCount: Number,
    maxCount: { type: Number, default: 20 }
  }

  connect() {
    this.failedFiles = new Map()
    this.refreshState()
  }

  async queueSelectedFiles(event) {
    if (event.target !== this.inputTarget) return

    this.hideNotices()

    // The Panels UI dropzone validates and normalizes this FileList before the
    // change event bubbles to the hotel queue controller.
    const files = Array.from(this.inputTarget.files || [])
    if (files.length === 0) return

    // Clear the transient dropzone previews. The attachment queue below is the
    // authoritative representation once staging begins.
    this.uploadFormTarget.reset()

    const remainingSlots = this.remainingSlots()
    if (remainingSlots <= 0) {
      this.showWarning(`You already reached the maximum of ${this.maxCountValue} photos.`)
      return
    }

    if (files.length > remainingSlots) {
      this.showWarning(`Only ${remainingSlots} more photo${remainingSlots === 1 ? "" : "s"} can be queued right now.`)
    }

    for (const file of files.slice(0, remainingSlots)) {
      // Keep uploads predictable and avoid race conditions in queue counters.
      // eslint-disable-next-line no-await-in-loop
      await this.uploadFile(file)
    }

    this.refreshState()
  }

  async removeQueuedPhoto(event) {
    this.hideNotices()

    const row = event.currentTarget.closest("[data-signed-id], [data-failed-id]")
    if (!row) return

    const failedId = row.dataset.failedId
    if (failedId) {
      this.failedFiles.delete(failedId)
      row.remove()
      this.refreshState()
      return
    }

    const signedId = row.dataset.signedId
    if (!signedId) return

    const response = await fetch(this.removeUrl(signedId), {
      method: "DELETE",
      headers: this.jsonHeaders()
    })

    if (!response.ok) {
      this.showError("Unable to remove queued photo.")
      return
    }

    row.remove()
    this.refreshState()
  }

  async retryUpload(event) {
    this.hideNotices()

    const row = event.currentTarget.closest("[data-failed-id]")
    if (!row) return

    const failedId = row.dataset.failedId
    const file = this.failedFiles.get(failedId)
    if (!file) return

    row.remove()
    this.failedFiles.delete(failedId)

    await this.uploadFile(file)
    this.refreshState()
  }

  async discardQueue() {
    this.hideNotices()

    const queuedRows = this.queuedRows()
    if (queuedRows.length === 0 && this.failedFiles.size === 0) return

    const response = await fetch(this.clearUrlValue, {
      method: "DELETE",
      headers: this.jsonHeaders()
    })

    if (!response.ok) {
      this.showError("Unable to discard queued photos.")
      return
    }

    queuedRows.forEach((row) => row.remove())
    this.failedFiles.clear()
    this.failedRows().forEach((row) => row.remove())
    this.refreshState()
  }

  async commitQueue() {
    this.hideNotices()

    if (this.queuedRows().length === 0) return

    this.confirmButtonTarget.disabled = true

    const response = await fetch(this.commitUrlValue, {
      method: "POST",
      headers: this.jsonHeaders()
    })

    if (!response.ok) {
      this.confirmButtonTarget.disabled = false
      this.showError("Unable to confirm queued photos. Please try again.")
      return
    }

    const data = await response.json()
    if (data.alert) this.showWarning(data.alert)
    window.location.reload()
  }

  async uploadFile(file) {
    const uploadRow = this.appendUploadingRow(file)
    const formData = new FormData()
    formData.append("photo", file)

    try {
      const response = await fetch(this.uploadUrlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": this.csrfToken(),
          "Accept": "application/json"
        },
        body: formData
      })

      if (!response.ok) {
        const payload = await this.safeJson(response)
        uploadRow.remove()
        this.appendFailedRow(file, payload?.error || "Upload failed. Retry this file.")
        return
      }

      const data = await response.json()
      uploadRow.replaceWith(this.buildQueuedRow(data.queue_item))
    } catch (_error) {
      uploadRow.remove()
      this.appendFailedRow(file, "Upload failed. Check your connection and try again.")
    }
  }

  appendUploadingRow(file) {
    const attachment = this.cloneAttachment(this.uploadTemplateTarget)
    this.updateAttachment(attachment, file.name, `Uploading · ${this.formatBytes(file.size)}`)
    this.queueListTarget.appendChild(attachment)
    return attachment
  }

  appendFailedRow(file, message) {
    const failedId = `${Date.now()}-${Math.random().toString(16).slice(2)}`
    this.failedFiles.set(failedId, file)

    const attachment = this.cloneAttachment(this.errorTemplateTarget)
    attachment.dataset.failedId = failedId
    this.updateAttachment(attachment, file.name, message)
    attachment.querySelector("[data-action~='hotel-photo-queue#removeQueuedPhoto']")
      ?.setAttribute("aria-label", `Remove failed upload ${file.name}`)

    this.queueListTarget.appendChild(attachment)
    this.showError("Some files could not be queued. Retry or remove failed items.")
  }

  buildQueuedRow(item) {
    const attachment = this.cloneAttachment(this.queuedTemplateTarget)
    attachment.dataset.signedId = item.signed_id
    this.updateAttachment(attachment, item.filename, `Queued · ${item.byte_size}`)

    const image = attachment.querySelector(".panel-attachment__media img")
    if (image) {
      image.src = item.preview_url
      image.alt = `Preview of ${item.filename}`
    }

    attachment.querySelector("[data-action~='hotel-photo-queue#removeQueuedPhoto']")
      ?.setAttribute("aria-label", `Remove ${item.filename} from upload queue`)
    return attachment
  }

  cloneAttachment(template) {
    const fragment = template.content.cloneNode(true)
    return fragment.querySelector(".panel-attachment")
  }

  updateAttachment(attachment, title, description) {
    attachment.querySelector(".panel-attachment__title").textContent = title
    attachment.querySelector(".panel-attachment__description").textContent = description
  }

  refreshState() {
    const queuedCount = this.queuedRows().length
    const failedCount = this.failedRows().length
    const totalAfterConfirm = this.existingCountValue + queuedCount

    this.counterTextTarget.textContent = `${totalAfterConfirm}/${this.maxCountValue} after confirm (${queuedCount} queued)`
    this.confirmButtonTarget.disabled = queuedCount === 0 || failedCount > 0
    this.discardButtonTarget.disabled = queuedCount === 0 && failedCount === 0
    this.emptyStateTarget.classList.toggle("hidden", queuedCount > 0 || failedCount > 0)
  }

  queuedRows() {
    return Array.from(this.queueListTarget.querySelectorAll("[data-signed-id]"))
  }

  failedRows() {
    return Array.from(this.queueListTarget.querySelectorAll("[data-failed-id]"))
  }

  remainingSlots() {
    return this.maxCountValue - this.existingCountValue - this.queuedRows().length
  }

  removeUrl(signedId) {
    return this.removeUrlTemplateValue.replace("__SIGNED_ID__", encodeURIComponent(signedId))
  }

  showWarning(message) {
    this.showNotice(this.warningTarget, message)
  }

  showError(message) {
    this.showNotice(this.errorTarget, message)
  }

  hideNotices() {
    this.warningTarget.classList.add("hidden")
    this.errorTarget.classList.add("hidden")
  }

  showNotice(target, message) {
    const content = target.querySelector(".panel-alert__content")
    if (content) content.textContent = message
    target.classList.remove("hidden")
  }

  jsonHeaders() {
    return {
      "X-CSRF-Token": this.csrfToken(),
      "Accept": "application/json"
    }
  }

  csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || ""
  }

  async safeJson(response) {
    try {
      return await response.json()
    } catch (_error) {
      return null
    }
  }

  formatBytes(bytes) {
    if (bytes === 0) return "0 Bytes"

    const units = ["Bytes", "KB", "MB", "GB"]
    const index = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
    const value = bytes / (1024 ** index)
    return `${value.toFixed(index === 0 ? 0 : 1)} ${units[index]}`
  }
}
