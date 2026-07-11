import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "dropzone", "previewContainer", "error"]
  static values = {
    existingCount: Number,
    maxCount: { type: Number, default: 10 }
  }

  connect() {
    this.selectedFiles = []
    this.previewUrls = []
    this.setupDragAndDrop()
  }

  disconnect() {
    this.clearPreviews()
  }

  setupDragAndDrop() {
    if (!this.hasDropzoneTarget) return

    const dropzone = this.dropzoneTarget

    // Bind event handlers to keep this context
    this.onDragEnter = this.onDragEnter.bind(this)
    this.onDragOver = this.onDragOver.bind(this)
    this.onDragLeave = this.onDragLeave.bind(this)
    this.onDrop = this.onDrop.bind(this)

    dropzone.addEventListener("dragenter", this.onDragEnter)
    dropzone.addEventListener("dragover", this.onDragOver)
    dropzone.addEventListener("dragleave", this.onDragLeave)
    dropzone.addEventListener("drop", this.onDrop)
  }

  onDragEnter(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzoneTarget.classList.add("border-blue-500", "bg-blue-50/50", "scale-[1.01]", "ring-4", "ring-blue-100")
    this.dropzoneTarget.classList.remove("border-slate-300", "bg-white", "group-hover:bg-slate-50", "group-hover:border-blue-400")
  }

  onDragOver(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzoneTarget.classList.add("border-blue-500", "bg-blue-50/50", "scale-[1.01]", "ring-4", "ring-blue-100")
    this.dropzoneTarget.classList.remove("border-slate-300", "bg-white", "group-hover:bg-slate-50", "group-hover:border-blue-400")
  }

  onDragLeave(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50/50", "scale-[1.01]", "ring-4", "ring-blue-100")
    this.dropzoneTarget.classList.add("border-slate-300", "bg-white", "group-hover:bg-slate-50", "group-hover:border-blue-400")
  }

  onDrop(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzoneTarget.classList.remove("border-blue-500", "bg-blue-50/50", "scale-[1.01]", "ring-4", "ring-blue-100")
    this.dropzoneTarget.classList.add("border-slate-300", "bg-white", "group-hover:bg-slate-50", "group-hover:border-blue-400")

    const files = e.dataTransfer.files
    if (files && files.length > 0) {
      this.handleFiles(files)
    }
  }

  // Triggered when file input changes
  onFileSelect(e) {
    const files = e.target.files
    if (files && files.length > 0) {
      this.handleFiles(files)
    }
  }

  handleFiles(filesList) {
    this.hideError()
    const files = Array.from(filesList)
    const validFiles = []
    let errors = []

    const remainingSlots = this.maxCountValue - this.existingCountValue - this.selectedFiles.length

    for (const file of files) {
      if (!file.type.startsWith("image/")) {
        errors.push(`"${file.name}" is not a valid image file.`)
        continue
      }

      if (file.size > 10 * 1024 * 1024) {
        errors.push(`"${file.name}" is larger than 10MB limit.`)
        continue
      }

      validFiles.push(file)
    }

    if (validFiles.length > remainingSlots) {
      errors.push(`Only ${remainingSlots} more photo(s) can be selected (limit is ${this.maxCountValue} total).`)
      validFiles.splice(remainingSlots)
    }

    if (errors.length > 0) {
      this.showError(errors.join(" "))
    }

    if (validFiles.length > 0) {
      this.selectedFiles = [...this.selectedFiles, ...validFiles]
      this.updateInputFiles()
      this.renderPreviews()
    }
  }

  removeFile(e) {
    const index = parseInt(e.currentTarget.dataset.index, 10)
    if (isNaN(index)) return

    this.selectedFiles.splice(index, 1)
    this.updateInputFiles()
    this.renderPreviews()
    this.hideError()
  }

  updateInputFiles() {
    const dataTransfer = new DataTransfer()
    this.selectedFiles.forEach(file => {
      dataTransfer.items.add(file)
    })
    this.inputTarget.files = dataTransfer.files
  }

  renderPreviews() {
    this.clearPreviews()

    if (this.selectedFiles.length === 0) {
      this.previewContainerTarget.classList.add("hidden")
      this.previewContainerTarget.innerHTML = ""
      return
    }

    this.previewContainerTarget.classList.remove("hidden")
    this.previewContainerTarget.innerHTML = ""

    // Create container title/header
    const header = document.createElement("div")
    header.className = "col-span-full flex items-center justify-between mb-2 border-b border-slate-200 pb-3"
    header.innerHTML = `
      <div class="flex items-center gap-x-2">
        <span class="flex h-2 w-2 rounded-full bg-blue-600 animate-pulse"></span>
        <h4 class="text-xs font-bold text-slate-800 uppercase tracking-widest">New Photos to Upload (${this.selectedFiles.length})</h4>
      </div>
      <button type="button" data-action="click->drag-drop-upload#clearAll" class="text-xs font-bold text-red-600 hover:text-red-700 transition-colors">Clear All</button>
    `
    this.previewContainerTarget.appendChild(header)

    this.selectedFiles.forEach((file, index) => {
      const objectUrl = URL.createObjectURL(file)
      this.previewUrls.push(objectUrl)

      const card = document.createElement("div")
      card.className = "relative group aspect-square rounded-2xl overflow-hidden border border-slate-200 bg-white shadow-sm transition-all duration-300 hover:shadow-md hover:scale-[1.02]"
      card.innerHTML = `
        <img src="${objectUrl}" class="w-full h-full object-cover transition-transform duration-500 group-hover:scale-110">
        <div class="absolute inset-0 bg-gradient-to-t from-slate-950/90 via-slate-950/20 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex flex-col justify-end p-3 pointer-events-none">
          <p class="text-xs font-semibold text-white truncate">${this.escapeHtml(file.name)}</p>
          <p class="text-[10px] text-slate-300 font-medium">${this.formatBytes(file.size)}</p>
        </div>
        <button type="button" 
                data-action="click->drag-drop-upload#removeFile" 
                data-index="${index}"
                class="absolute top-3 right-3 flex h-7 w-7 items-center justify-center rounded-full bg-slate-900/80 text-white shadow-sm backdrop-blur-sm transition-all duration-200 hover:bg-red-600 hover:scale-110 active:scale-95"
                aria-label="Remove photo">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
        </button>
      `
      this.previewContainerTarget.appendChild(card)
    })
  }

  clearAll(e) {
    if (e) e.preventDefault()
    this.selectedFiles = []
    this.updateInputFiles()
    this.renderPreviews()
    this.hideError()
  }

  clearPreviews() {
    this.previewUrls.forEach(url => URL.revokeObjectURL(url))
    this.previewUrls = []
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  hideError() {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  formatBytes(bytes, decimals = 1) {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const dm = decimals < 0 ? 0 : decimals
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i]
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
