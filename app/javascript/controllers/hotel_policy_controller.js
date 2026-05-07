import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "hiddenInput"]
  static values = {
    initial: Array
  }

  connect() {
    this.items = this.normalizeInitialItems().map(item => ({ ...item, editing: false }))
    this.render()
    this.sync()
  }

  addItem(event) {
    if (event) event.preventDefault()
    this.items.push({ title: "", content: "", editing: true })
    this.render()
    this.sync()
  }

  toggleEdit(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const isEditing = this.items[index].editing

    if (!isEditing) {
      this.items[index].editing = true
      this.render()
      return
    }

    this.save().then(success => {
      if (!success) return

      this.items[index].editing = false
      this.render()
    })
  }

  removeItem(event) {
    event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.items.splice(index, 1)
    this.render()
    this.sync()
    this.save()
  }

  updateItem(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    const field = event.currentTarget.dataset.field
    this.items[index][field] = event.target.value
    this.sync()
  }

  sync() {
    const data = this.items.map(({ editing, ...rest }) => rest)
    this.hiddenInputTarget.value = JSON.stringify(data)
  }

  render() {
    this.containerTarget.innerHTML = ""

    if (this.items.length === 0) {
      this.renderEmptyState()
      return
    }

    this.items.forEach((item, index) => {
      this.containerTarget.appendChild(item.editing ? this.createEditElement(item, index) : this.createViewElement(item, index))
    })
  }

  async save() {
    this.sync()

    const response = await fetch(this.element.action, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: new FormData(this.element)
    })

    if (!response.ok) {
      return false
    }

    return true
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }

  normalizeInitialItems() {
    const value = this.element.dataset.hotelPolicyInitialValue

    if (!value) return []

    try {
      const parsed = JSON.parse(value)
      return Array.isArray(parsed) ? parsed : []
    } catch (_error) {
      return []
    }
  }

  renderEmptyState() {
    const div = document.createElement("div")
    div.className = "flex flex-col items-center justify-center rounded-[28px] border border-dashed border-slate-300 bg-white/90 px-6 py-16 text-center shadow-sm"
    div.innerHTML = `
      <div class="mb-5 rounded-full border border-slate-200 bg-slate-50 p-4 shadow-sm">
        <svg class="h-6 w-6 text-slate-500" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M8 9h8"/><path d="M8 13h6"/></svg>
      </div>
      <h3 class="text-xl font-semibold tracking-tight text-slate-950">Add your first policy</h3>
      <p class="mt-2 max-w-md text-sm leading-6 text-slate-500">Create clear, reusable blocks for quiet hours, smoking, pets, access rules, and other important stay expectations.</p>
      <button type="button" data-action="click->hotel-policy#addItem" class="mt-6 inline-flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-slate-800">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
        Create First Policy
      </button>
    `
    this.containerTarget.appendChild(div)
  }

  createViewElement(item, index) {
    const div = document.createElement("div")
    div.className = "group relative overflow-hidden rounded-[24px] border border-slate-200 bg-white p-6 shadow-sm transition-all hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-lg hover:shadow-slate-200/60"
    div.innerHTML = `
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-2">
          <h4 class="text-lg font-semibold tracking-tight text-slate-950">${this.escapeHtml(item.title) || "Untitled Policy"}</h4>
        </div>
        <div class="flex items-center gap-2">
          <button type="button"
                  class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 transition-all hover:border-slate-300 hover:bg-slate-50"
                  data-index="${index}"
                  data-action="click->hotel-policy#toggleEdit">
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
            Edit
          </button>
          <button type="button"
                  class="rounded-lg p-2 text-slate-400 transition-colors hover:bg-red-50 hover:text-red-500"
                  data-index="${index}"
                  data-action="click->hotel-policy#removeItem">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
          </button>
        </div>
      </div>
      <div class="mt-6 rounded-2xl border border-slate-100 bg-slate-50/60 p-4">
        <p class="text-sm leading-6 text-slate-600">${this.escapeHtml(item.content) || "..."}</p>
      </div>
    `
    return div
  }

  createEditElement(item, index) {
    const div = document.createElement("div")
    div.className = "rounded-[26px] border border-slate-200 bg-white p-6 shadow-xl shadow-slate-200/70 ring-1 ring-slate-200/80 animate-in fade-in zoom-in duration-200"
    div.innerHTML = `
      <div class="mb-6 border-b border-slate-100 pb-5">
        <div class="max-w-2xl">
          <label class="mb-2 block text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-400">Policy Title</label>
          <input type="text"
                 class="w-full rounded-2xl border border-slate-200 bg-slate-50/70 px-4 py-3 text-base font-semibold tracking-tight text-slate-950 outline-none transition-all focus:border-slate-300 focus:bg-white focus:ring-2 focus:ring-slate-200"
                 placeholder="e.g., Quiet Hours"
                 value="${this.escapeHtml(item.title)}"
                 data-index="${index}"
                 data-field="title"
                 data-action="input->hotel-policy#updateItem">
        </div>
      </div>

      <div class="space-y-6">
        <div class="space-y-1">
          <label class="block text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-400">Policy Content</label>
          <textarea class="w-full rounded-2xl border border-slate-200 bg-slate-50/70 px-4 py-3 text-sm leading-6 text-slate-600 outline-none transition-all focus:border-slate-300 focus:bg-white focus:ring-2 focus:ring-slate-200"
                    placeholder="Write the policy details..."
                    rows="5"
                    data-index="${index}"
                    data-field="content"
                    data-action="input->hotel-policy#updateItem">${this.escapeHtml(item.content)}</textarea>
        </div>

        <div class="flex items-center justify-end gap-2 border-t border-slate-100 pt-5">
          <button type="button"
                  class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-600 transition-all hover:border-red-200 hover:bg-red-50 hover:text-red-600"
                  data-index="${index}"
                  data-action="click->hotel-policy#removeItem">
            Delete
          </button>
          <button type="button"
                  class="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-4 py-2 text-xs font-semibold text-white shadow-sm transition-all hover:bg-slate-800"
                  data-index="${index}"
                  data-action="click->hotel-policy#toggleEdit">
            Done and Save
          </button>
        </div>
      </div>
    `
    return div
  }

  escapeHtml(unsafe) {
    return (unsafe || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
