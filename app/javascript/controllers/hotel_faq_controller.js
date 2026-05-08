import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container", "hiddenInput"]
  static values = {
    initial: Array
  }

  connect() {
    // Each section now tracks its own editing state
    this.sections = (this.initialValue || []).map(section => ({
      ...section,
      editing: false
    }))
    this.render()
  }

  addSection(e) {
    if (e) e.preventDefault()
    this.sections.push({
      section_name: "",
      items: [{ question: "", answer: "" }],
      editing: true
    })
    this.render()
    this.sync()
  }

  toggleEdit(e) {
    e.preventDefault()
    const index = parseInt(e.currentTarget.dataset.index, 10)
    const isEditing = this.sections[index].editing

    if (!isEditing) {
      this.sections[index].editing = true
      this.render()
      return
    }

    this.save().then(success => {
      if (!success) return

      this.sections[index].editing = false
      this.render()
    })
  }

  removeSection(e) {
    e.preventDefault()
    if (!confirm("Are you sure you want to remove this entire section?")) return
    
    const index = parseInt(e.currentTarget.dataset.index)
    this.sections.splice(index, 1)
    this.render()
    this.sync()
    this.save()
  }

  addItem(e) {
    e.preventDefault()
    const sectionIndex = parseInt(e.currentTarget.dataset.sectionIndex)
    this.sections[sectionIndex].items.push({ question: "", answer: "" })
    this.render()
    this.sync()
  }

  removeItem(e) {
    e.preventDefault()
    const sectionIndex = parseInt(e.currentTarget.dataset.sectionIndex)
    const itemIndex = parseInt(e.currentTarget.dataset.itemIndex)
    this.sections[sectionIndex].items.splice(itemIndex, 1)
    
    // If we removed the last item, add an empty one back or let it be empty
    if (this.sections[sectionIndex].items.length === 0) {
      this.sections[sectionIndex].items.push({ question: "", answer: "" })
    }
    
    this.render()
    this.sync()
    this.save()
  }

  updateSectionName(e) {
    const index = parseInt(e.currentTarget.dataset.index)
    this.sections[index].section_name = e.target.value
    this.sync()
  }

  updateItem(e) {
    const sectionIndex = parseInt(e.currentTarget.dataset.sectionIndex)
    const itemIndex = parseInt(e.currentTarget.dataset.itemIndex)
    const field = e.currentTarget.dataset.field
    this.sections[sectionIndex].items[itemIndex][field] = e.target.value
    this.sync()
  }

  sync() {
    const dataToSync = this.sections.map(({ editing, ...rest }) => rest)
    this.hiddenInputTarget.value = JSON.stringify(dataToSync)
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

  render() {
    this.containerTarget.innerHTML = ""
    
    if (this.sections.length === 0) {
      this.renderEmptyState()
      return
    }

    this.sections.forEach((section, sIndex) => {
      if (section.editing) {
        this.containerTarget.appendChild(this.createEditElement(section, sIndex))
      } else {
        this.containerTarget.appendChild(this.createViewElement(section, sIndex))
      }
    })
  }

  renderEmptyState() {
    const div = document.createElement("div")
    div.className = "flex flex-col items-center justify-center rounded-[28px] border border-dashed border-slate-300 bg-white/90 px-6 py-16 text-center shadow-sm"
    div.innerHTML = `
      <div class="mb-5 rounded-full border border-slate-200 bg-slate-50 p-4 shadow-sm">
        <svg class="h-6 w-6 text-slate-500" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/><path d="M8 13h8"/><path d="M8 17h5"/></svg>
      </div>
      <p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-slate-400">Start Here</p>
      <h3 class="mt-2 text-xl font-semibold tracking-tight text-slate-950">Build your FAQ library</h3>
      <p class="mt-2 max-w-md text-sm leading-6 text-slate-500">Organize guest answers into clear sections your team can update anytime, from arrival basics to amenities and local guidance.</p>
      <button type="button" data-action="click->hotel-faq#addSection" class="mt-6 inline-flex items-center gap-2 rounded-xl bg-slate-900 px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition hover:bg-slate-800">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14"/><path d="M12 5v14"/></svg>
        Create First Section
      </button>
    `
    this.containerTarget.appendChild(div)
  }

  createViewElement(section, index) {
    const div = document.createElement("div")
    div.className = "group relative overflow-hidden rounded-[24px] border border-slate-200 bg-white p-6 shadow-sm transition-all hover:-translate-y-0.5 hover:border-slate-300 hover:shadow-lg hover:shadow-slate-200/60"
    
    const itemsCount = section.items.filter(i => i.question || i.answer).length
    
    div.innerHTML = `
      <div class="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-slate-200 to-transparent"></div>
      <div class="flex items-start justify-between gap-4">
        <div class="space-y-2">
          <h4 class="text-lg font-semibold tracking-tight text-slate-950">${this.escapeHtml(section.section_name) || "Untitled Section"}</h4>
          <div class="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-[11px] font-semibold uppercase tracking-[0.12em] text-slate-600">${itemsCount} Question${itemsCount === 1 ? '' : 's'}</div>
        </div>
        <div class="flex items-center gap-2">
          <button type="button" 
                  class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-700 transition-all hover:border-slate-300 hover:bg-slate-50" 
                  data-index="${index}" 
                  data-action="click->hotel-faq#toggleEdit">
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/><path d="m15 5 4 4"/></svg>
            Edit
          </button>
          <button type="button" 
                  class="rounded-lg p-2 text-slate-400 transition-colors hover:bg-red-50 hover:text-red-500" 
                  data-index="${index}" 
                  data-action="click->hotel-faq#removeSection">
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
          </button>
        </div>
      </div>
      <div class="mt-6 space-y-3 rounded-2xl border border-slate-100 bg-slate-50/60 p-4">
        ${section.items.map(item => `
          <div class="text-sm">
            <p class="font-semibold text-slate-900">Q: ${this.escapeHtml(item.question) || "..."}</p>
            <p class="mt-1 line-clamp-2 leading-6 text-slate-500">${this.escapeHtml(item.answer) || "..."}</p>
          </div>
        `).join("")}
      </div>
    `
    return div
  }

  createEditElement(section, index) {
    const div = document.createElement("div")
    div.className = "rounded-[26px] border border-slate-200 bg-white p-6 shadow-xl shadow-slate-200/70 ring-1 ring-slate-200/80 animate-in fade-in zoom-in duration-200"
    div.innerHTML = `
      <div class="mb-6 border-b border-slate-100 pb-5">
        <div class="max-w-2xl">
          <label class="mb-2 block text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-400">Section Title</label>
          <input type="text" 
                 class="w-full rounded-2xl border border-slate-200 bg-slate-50/70 px-4 py-3 text-base font-semibold tracking-tight text-slate-950 outline-none transition-all focus:border-slate-300 focus:bg-white focus:ring-2 focus:ring-slate-200" 
                 placeholder="e.g., Arrival & Check-in" 
                 value="${this.escapeHtml(section.section_name)}" 
                 data-index="${index}" 
                  data-action="input->hotel-faq#updateSectionName">
        </div>
      </div>

      <div class="space-y-6">
        <div class="flex items-center justify-between gap-4">
          <label class="block text-[11px] font-semibold uppercase tracking-[0.14em] text-slate-400">Questions & Answers</label>
          <span class="text-xs text-slate-400">Write responses the team can reuse consistently.</span>
        </div>
        <div class="space-y-4">
          ${section.items.map((item, iIndex) => `
            <div class="relative rounded-2xl border border-slate-200/80 bg-slate-50/65 p-5 transition-all hover:border-slate-300 hover:bg-white">
              <div class="flex items-start gap-4">
                <div class="flex-grow space-y-3">
                  <div class="space-y-1">
                    <label class="block text-[11px] font-semibold uppercase tracking-[0.12em] text-slate-400">Question</label>
                    <input type="text" 
                           class="w-full border-none bg-transparent p-0 text-sm font-semibold text-slate-900 placeholder:text-slate-400 focus:ring-0 outline-none" 
                           placeholder="Enter question here..." 
                           value="${this.escapeHtml(item.question)}" 
                           data-section-index="${index}" 
                           data-item-index="${iIndex}" 
                           data-field="question" 
                           data-action="input->hotel-faq#updateItem">
                    <div class="h-px w-full bg-slate-200 transition-colors"></div>
                  </div>
                  <div class="space-y-1">
                    <label class="block text-[11px] font-semibold uppercase tracking-[0.12em] text-slate-400">Answer</label>
                    <textarea class="w-full resize-none border-none bg-transparent p-0 text-sm leading-6 text-slate-600 placeholder:text-slate-400 focus:ring-0 outline-none" 
                             placeholder="Write the answer..." 
                             rows="2"
                             data-section-index="${index}" 
                             data-item-index="${iIndex}" 
                             data-field="answer" 
                             data-action="input->hotel-faq#updateItem">${this.escapeHtml(item.answer)}</textarea>
                  </div>
                </div>
                <button type="button" 
                        class="rounded-lg p-2 text-slate-300 transition-colors hover:bg-red-50 hover:text-red-500" 
                        data-section-index="${index}" 
                        data-item-index="${iIndex}" 
                        data-action="click->hotel-faq#removeItem">
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14c0 1-1 2-2 2H7c-1 0-2-1-2-2V6"/><path d="M8 6V4c0-1 1-2 2-2h4c1 0 2 1 2 2v2"/></svg>
                </button>
              </div>
            </div>
          `).join("")}
        </div>
        
        <button type="button" 
                class="flex w-full items-center justify-center gap-2 rounded-2xl border border-dashed border-slate-300 bg-white/80 py-3.5 text-sm font-semibold text-slate-600 transition-all hover:border-slate-400 hover:bg-white hover:text-slate-700" 
                data-section-index="${index}" 
                data-action="click->hotel-faq#addItem">
          <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14"/><path d="M5 12h14"/></svg>
          Add Another Question
        </button>

        <div class="flex items-center justify-end gap-2 border-t border-slate-100 pt-5">
          <button type="button" 
                  class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs font-semibold text-slate-600 transition-all hover:border-red-200 hover:bg-red-50 hover:text-red-600" 
                  data-index="${index}" 
                  data-action="click->hotel-faq#removeSection">
            Delete
          </button>
          <button type="button" 
                  class="inline-flex items-center gap-1.5 rounded-xl bg-slate-900 px-4 py-2 text-xs font-semibold text-white shadow-sm transition-all hover:bg-slate-800" 
                  data-index="${index}" 
                  data-action="click->hotel-faq#toggleEdit">
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
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
