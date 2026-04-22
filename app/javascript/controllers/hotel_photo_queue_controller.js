import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "queueList", "emptyState", "counterText", "warning", "error", "confirmButton", "discardButton"]
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

  async queueSelectedFiles() {
    this.hideNotices()

    const files = Array.from(this.inputTarget.files || [])
    if (files.length === 0) return

    let remainingSlots = this.remainingSlots()
    if (remainingSlots <= 0) {
      this.showWarning(`You already reached the maximum of ${this.maxCountValue} photos.`)
      this.inputTarget.value = ""
      return
    }

    if (files.length > remainingSlots) {
      this.showWarning(`Only ${remainingSlots} more photo${remainingSlots === 1 ? "" : "s"} can be queued right now.`)
    }

    const queueableFiles = files.slice(0, remainingSlots)
    for (const file of queueableFiles) {
      // Keep uploads predictable and avoid race conditions in queue counters.
      // eslint-disable-next-line no-await-in-loop
      await this.uploadFile(file)
    }

    this.inputTarget.value = ""
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
  }

  appendUploadingRow(file) {
    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center justify-between gap-3 rounded-xl border border-slate-200 bg-white p-3"
    wrapper.innerHTML = `
      <div class="min-w-0">
        <p class="truncate text-sm font-medium text-slate-900">${this.escapeHtml(file.name)}</p>
        <p class="text-xs text-slate-500">Uploading...</p>
      </div>
      <span class="text-xs font-semibold text-slate-500">Processing</span>
    `
    this.queueListTarget.appendChild(wrapper)
    return wrapper
  }

  appendFailedRow(file, message) {
    const failedId = `${Date.now()}-${Math.random().toString(16).slice(2)}`
    this.failedFiles.set(failedId, file)

    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center justify-between gap-3 rounded-xl border border-rose-200 bg-rose-50 p-3"
    wrapper.dataset.failedId = failedId
    wrapper.innerHTML = `
      <div class="min-w-0">
        <p class="truncate text-sm font-medium text-rose-900">${this.escapeHtml(file.name)}</p>
        <p class="text-xs text-rose-700">${this.escapeHtml(message)}</p>
      </div>
      <div class="flex items-center gap-2">
        <button type="button" class="rounded-lg border border-rose-200 bg-white px-3 py-1.5 text-xs font-semibold text-rose-700 hover:bg-rose-100" data-action="hotel-photo-queue#retryUpload">Retry</button>
        <button type="button" class="rounded-lg border border-rose-200 bg-white px-3 py-1.5 text-xs font-semibold text-rose-700 hover:bg-rose-100" data-action="hotel-photo-queue#removeQueuedPhoto">Remove</button>
      </div>
    `

    this.queueListTarget.appendChild(wrapper)
    this.showError("Some files could not be queued. Retry or remove failed items.")
  }

  buildQueuedRow(item) {
    const wrapper = document.createElement("div")
    wrapper.className = "flex items-center justify-between gap-3 rounded-xl border border-slate-200 bg-white p-3"
    wrapper.dataset.signedId = item.signed_id
    wrapper.innerHTML = `
      <div class="flex min-w-0 items-center gap-3">
        <img src="${item.preview_url}" alt="${this.escapeHtml(item.filename)}" class="h-12 w-12 rounded-lg border border-slate-200 object-cover">
        <div class="min-w-0">
          <p class="truncate text-sm font-medium text-slate-900">${this.escapeHtml(item.filename)}</p>
          <p class="text-xs text-slate-500">${this.escapeHtml(item.byte_size)}</p>
        </div>
      </div>
      <button type="button" class="rounded-lg border border-slate-200 px-3 py-1.5 text-xs font-semibold text-slate-700 transition hover:bg-slate-100" data-action="hotel-photo-queue#removeQueuedPhoto">Remove</button>
    `
    return wrapper
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
    this.warningTarget.textContent = message
    this.warningTarget.classList.remove("hidden")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideNotices() {
    this.warningTarget.classList.add("hidden")
    this.errorTarget.classList.add("hidden")
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

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;")
  }
}
