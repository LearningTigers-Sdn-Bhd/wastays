import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dialog",
    "confirmDialog",
    "confirmMessage",
    "form",
    "title",
    "subtitle",
    "mode",
    "startDate",
    "endDate",
    "roomTypeOption",
    "roomTypeCheckbox",
    "roomTypeSearch",
    "ratePlanOption",
    "ratePlanCheckbox",
    "ratePlanSearch",
    "applyInventory",
    "applyRates",
    "applyRestrictions",
    "inventoryFields",
    "rateFields",
    "restrictionFields",
    "ratePlanFields",
    "quantityField",
    "statusField",
    "currentStatusHint",
    "priceField",
    "currencyField",
    "minStayField",
    "maxStayField",
    "ctaField",
    "ctdField",
    "stopSellField",
    "submitButton",
    "syncButton",
    "syncCounter",
    "reviewDialog",
    "reviewList",
    "finalSyncButton"
  ]

  static values = {
    hotelId: String,
    defaultMode: String,
    defaultStart: String,
    defaultEnd: String,
    defaultCurrency: String
  }

  initialize() {
    this.stagedChanges = []
  }

  connect() {
    this.skipConfirm = false
    this.setMode(this.defaultModeValue || "availability")
    this.filterRoomTypes()
    this.filterRatePlans()
    this.syncRatePlans()
    this.toggleSections()
    this.loadStagedChanges()
    this.updateSyncButton()
  }

  loadStagedChanges() {
    const key = `ari_staged_${this.hotelIdValue}`
    const stored = localStorage.getItem(key)
    if (!stored) return

    try {
      const { timestamp, changes } = JSON.parse(stored)
      const now = new Date().getTime()
      const thirtyMinutes = 30 * 60 * 1000

      if (now - timestamp > thirtyMinutes) {
        localStorage.removeItem(key)
        return
      }

      this.stagedChanges = changes
      this.stagedChanges.forEach(change => this.highlightStagedCells(change))
    } catch (e) {
      console.error("Failed to load staged changes", e)
      localStorage.removeItem(key)
    }
  }

  saveStagedChanges() {
    const key = `ari_staged_${this.hotelIdValue}`
    const data = {
      timestamp: new Date().getTime(),
      changes: this.stagedChanges
    }
    localStorage.setItem(key, JSON.stringify(data))
  }

  clearStorage() {
    const key = `ari_staged_${this.hotelIdValue}`
    localStorage.removeItem(key)
  }

  openBulk(event) {
    if (event) event.preventDefault()
    this.resetForm()
    this.titleTarget.textContent = "Bulk Edit"
    this.subtitleTarget.textContent = "Stage updates across a date range and multiple categories."
    this.submitButtonTarget.value = "Stage Changes"
    this.currentStatusHintTarget.textContent = ""
    this.openDialog()
  }

  openCell(event) {
    const data = event.currentTarget.dataset

    this.resetForm()
    this.setMode(data.mode || this.currentMode())
    this.startDateTarget.value = data.date
    this.endDateTarget.value = data.date
    
    // Select the specific room type
    this.roomTypeCheckboxTargets.forEach(cb => {
      cb.checked = (cb.value === data.roomTypeId)
    })

    this.syncRatePlans()

    // Select the specific rate plan if applicable
    if (data.ratePlanId) {
      this.ratePlanCheckboxTargets.forEach(cb => {
        cb.checked = (cb.value === data.ratePlanId)
      })
    }

    if (data.mode === "availability") {
      this.quantityFieldTarget.value = data.quantity || ""
      this.statusFieldTarget.value = ""
      
      const current = data.status || "open"
      this.currentStatusHintTarget.textContent = `Currently: ${current.toUpperCase()}`
    } else {
      this.currentStatusHintTarget.textContent = ""
      this.priceFieldTarget.value = data.price || ""
      
      const currency = data.currency || this.defaultCurrencyValue || "MYR"
      this.currencyFieldTarget.value = currency
      
      const searchableSelect = this.currencyFieldTarget.closest('[data-controller="searchable-select"]')
      if (searchableSelect) {
        const input = searchableSelect.querySelector('[data-searchable-select-target="input"]')
        const option = searchableSelect.querySelector(`[data-value="${currency}"]`)
        if (input && option) input.value = option.dataset.label
      }

      this.minStayFieldTarget.value = data.minStay || ""
      this.maxStayFieldTarget.value = data.maxStay || ""
      this.ctaFieldTarget.checked = data.closedToArrival === "true"
      this.ctdFieldTarget.checked = data.closedToDeparture === "true"
      this.stopSellFieldTarget.checked = data.stopSell === "true"
    }

    this.titleTarget.textContent = this.titleForMode(data.mode || this.currentMode())
    this.subtitleTarget.textContent = `Staging update for ${data.date}`
    this.submitButtonTarget.value = "Stage Update"
    this.openDialog()
  }

  close(event) {
    if (event) event.preventDefault()
    this.dialogTarget.close()
    this.skipConfirm = false
  }

  confirmSubmit(event) {
    // We are overriding the direct submission to stage the change
    event.preventDefault()
    this.stageCurrentSelection()
    this.close()
  }

  stageCurrentSelection() {
    const selectedRoomTypes = this.roomTypeCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => ({ id: cb.value, name: cb.closest("label").querySelector("span").textContent.trim() }))
    
    const selectedRatePlans = this.ratePlanCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => ({ id: cb.value, name: cb.closest("label").querySelector("span").textContent.trim() }))
    
    const change = {
      id: Math.random().toString(36).substr(2, 9),
      start_date: this.startDateTarget.value,
      end_date: this.endDateTarget.value,
      room_type_ids: selectedRoomTypes.map(rt => rt.id),
      rate_plan_ids: selectedRatePlans.map(rp => rp.id),
      apply_inventory: this.applyInventoryTarget.checked,
      apply_rates: this.applyRatesTarget.checked,
      apply_restrictions: this.applyRestrictionsTarget.checked,
      quantity: this.quantityFieldTarget.value,
      status: this.statusFieldTarget.value,
      price: this.priceFieldTarget.value,
      currency: this.currencyFieldTarget.value,
      min_stay: this.minStayFieldTarget.value,
      max_stay: this.maxStayFieldTarget.value,
      closed_to_arrival: this.ctaFieldTarget.checked,
      closed_to_departure: this.ctdFieldTarget.checked,
      stop_sell: this.stopSellFieldTarget.checked,
      summary: this.buildSummary(selectedRoomTypes, selectedRatePlans)
    }

    this.stagedChanges.push(change)
    this.saveStagedChanges()
    this.updateSyncButton()
    this.highlightStagedCells(change)
  }

  buildSummary(selectedRoomTypes, selectedRatePlans) {
    const actions = []
    const details = []
    
    if (this.applyInventoryTarget.checked) {
      actions.push("Inventory")
      const invParts = []
      if (this.quantityFieldTarget.value !== "") invParts.push(`Qty: ${this.quantityFieldTarget.value}`)
      if (this.statusFieldTarget.value !== "") invParts.push(`Status: ${this.statusFieldTarget.value}`)
      if (invParts.length > 0) details.push(invParts.join(", "))
    }
    
    if (this.applyRatesTarget.checked) {
      actions.push("Rates")
      details.push(`Price: ${this.currencyFieldTarget.value} ${this.priceFieldTarget.value}`)
    }
    
    if (this.applyRestrictionsTarget.checked) {
      actions.push("Restrictions")
      const restr = []
      if (this.minStayFieldTarget.value) restr.push(`Min Stay: ${this.minStayFieldTarget.value}`)
      if (this.maxStayFieldTarget.value) restr.push(`Max Stay: ${this.maxStayFieldTarget.value}`)
      if (this.ctaFieldTarget.checked) restr.push("CTA")
      if (this.ctdFieldTarget.checked) restr.push("CTD")
      if (this.stopSellFieldTarget.checked) restr.push("Stop Sell")
      if (restr.length > 0) details.push(restr.join(", "))
    }
    
    const start = this.formatDate(this.startDateTarget.value)
    const end = this.formatDate(this.endDateTarget.value)
    const dates = this.startDateTarget.value === this.endDateTarget.value 
      ? start 
      : `${start} to ${end}`

    return {
      actions: actions.join(", "),
      details: details.join(" | "),
      dates: dates,
      rooms: selectedRoomTypes.map(rt => rt.name).join(", "),
      plans: selectedRatePlans.map(rp => rp.name).join(", ")
    }
  }

  formatDate(dateString) {
    if (!dateString) return ""
    const date = new Date(dateString)
    return date.toLocaleDateString("en-GB", {
      day: "numeric",
      month: "long",
      year: "numeric"
    })
  }

  updateSyncButton() {
    const count = this.stagedChanges.length
    this.syncButtonTarget.disabled = count === 0
    this.syncCounterTarget.textContent = count
    this.syncCounterTarget.classList.toggle("hidden", count === 0)
  }

  highlightStagedCells(change) {
    const dates = this.getDatesInRange(change.start_date, change.end_date)
    
    dates.forEach(date => {
      change.room_type_ids.forEach(roomTypeId => {
        if (change.apply_inventory) {
          this.markCellDirty(`availability-cell-${roomTypeId}-${date}`, {
            quantity: change.quantity,
            status: change.status
          })
        }
        
        if (change.apply_rates || change.apply_restrictions) {
          change.rate_plan_ids.forEach(ratePlanId => {
            this.markCellDirty(`rate-cell-${roomTypeId}-${ratePlanId}-${date}`, {
              price: change.apply_rates ? change.price : undefined,
              currency: change.currency,
              min_stay: change.apply_restrictions ? change.min_stay : undefined,
              max_stay: change.apply_restrictions ? change.max_stay : undefined,
              closed_to_arrival: change.apply_restrictions ? change.closed_to_arrival : undefined,
              closed_to_departure: change.apply_restrictions ? change.closed_to_departure : undefined,
              stop_sell: change.apply_restrictions ? change.stop_sell : undefined
            })
          })
        }
      })
    })
  }

  getDatesInRange(startDate, endDate) {
    const dates = []
    let curr = new Date(startDate)
    const last = new Date(endDate)
    while (curr <= last) {
      dates.push(curr.toISOString().split("T")[0])
      curr.setDate(curr.getDate() + 1)
    }
    return dates
  }

  markCellDirty(testid, data = null) {
    const cell = this.element.querySelector(`[data-testid="${testid}"]`)
    if (cell) {
      cell.classList.add("ring-2", "ring-inset", "ring-indigo-500", "after:content-['*']", "after:absolute", "after:top-0", "after:right-1", "after:text-[10px]", "after:font-black", "after:text-indigo-600")
      cell.style.position = "relative"
      
      // Update dataset with pending values so re-editing shows the correct data
      if (data) {
        if (data.quantity !== undefined && data.quantity !== "") cell.dataset.quantity = data.quantity
        if (data.status !== undefined && data.status !== "") cell.dataset.status = data.status
        if (data.price !== undefined && data.price !== "") {
          cell.dataset.price = data.price
          const priceSpan = cell.querySelector(".tabular-nums")
          if (priceSpan) {
            const symbol = data.currency === "USD" ? "$" : "RM"
            const formatted = parseFloat(data.price).toLocaleString(undefined, {
              minimumFractionDigits: 0,
              maximumFractionDigits: 2
            })
            priceSpan.textContent = `${symbol}${formatted}`
          }
        }
        if (data.min_stay !== undefined && data.min_stay !== "") cell.dataset.minStay = data.min_stay
        if (data.max_stay !== undefined && data.max_stay !== "") cell.dataset.maxStay = data.max_stay
        if (data.closed_to_arrival !== undefined) cell.dataset.closedToArrival = data.closed_to_arrival ? "true" : "false"
        if (data.closed_to_departure !== undefined) cell.dataset.closedToDeparture = data.closed_to_departure ? "true" : "false"
        if (data.stop_sell !== undefined) cell.dataset.stopSell = data.stop_sell ? "true" : "false"
      }
    }
  }

  clearAllHighlights() {
    this.element.querySelectorAll(".ring-indigo-500").forEach(cell => {
      cell.classList.remove("ring-2", "ring-inset", "ring-indigo-500", "after:content-['*']", "after:absolute", "after:top-0", "after:right-1", "after:text-[10px]", "after:font-black", "after:text-indigo-600")
    })
  }

  clearStaged(event) {
    if (event) event.preventDefault()
    if (!confirm("Are you sure you want to clear all pending changes?")) return
    this.stagedChanges = []
    this.clearAllHighlights()
    this.clearStorage()
    this.updateSyncButton()
    this.closeReview()
  }

  openReview(event) {
    if (event) event.preventDefault()
    this.renderReviewList()
    this.reviewDialogTarget.showModal()
  }

  closeReview(event) {
    if (event) event.preventDefault()
    this.reviewDialogTarget.close()
  }

  renderReviewList() {
    this.reviewListTarget.innerHTML = this.stagedChanges.map(change => {
      const start = this.formatDate(change.start_date)
      const end = this.formatDate(change.end_date)
      const dateDisplay = change.start_date === change.end_date ? start : `${start} to ${end}`
      
      const detailsDisplay = change.summary.details.replace(/([A-Z]{3})(\d)/g, '$1 $2')

      return `
        <div class="rounded-xl border border-indigo-100 bg-indigo-50/30 p-4 shadow-sm space-y-3">
          <div class="flex items-start justify-between">
            <div class="space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="inline-flex items-center rounded-md bg-indigo-100 px-1.5 py-0.5 text-[10px] font-black uppercase tracking-wider text-indigo-700">${change.summary.actions}</span>
                <span class="text-xs font-black text-slate-900">${dateDisplay}</span>
              </div>
              <p class="text-[11px] font-bold text-indigo-600">${detailsDisplay}</p>
            </div>
            <button type="button" data-action="inventory-calendar#removeStaged" data-change-id="${change.id}" class="rounded-lg p-1 text-slate-400 hover:bg-red-50 hover:text-red-600 transition-all">
              <svg class="size-4" xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18"/><path d="m6 6 12 12"/></svg>
            </button>
          </div>
          
          <div class="grid gap-2 border-t border-indigo-100/50 pt-2 text-[10px]">
            <div>
              <span class="font-black uppercase tracking-wider text-slate-400">Rooms:</span>
              <span class="font-bold text-slate-700">${change.summary.rooms}</span>
            </div>
            ${change.summary.plans ? `
            <div>
              <span class="font-black uppercase tracking-wider text-slate-400">Plans:</span>
              <span class="font-bold text-slate-700">${change.summary.plans}</span>
            </div>
            ` : ""}
          </div>
        </div>
      `
    }).join("")

    if (this.stagedChanges.length === 0) {
      this.reviewListTarget.innerHTML = `<p class="py-12 text-center text-sm font-medium text-slate-500">No pending changes to sync.</p>`
    }
  }

  removeStaged(event) {
    const id = event.currentTarget.dataset.changeId
    this.stagedChanges = this.stagedChanges.filter(c => c.id !== id)
    this.saveStagedChanges()
    this.renderReviewList()
    this.updateSyncButton()
    if (this.stagedChanges.length === 0) {
      this.clearAllHighlights()
      this.clearStorage()
      this.closeReview()
    }
  }

  async submitStaged(event) {
    if (event) event.preventDefault()
    
    this.finalSyncButtonTarget.disabled = true
    this.finalSyncButtonTarget.textContent = "Syncing..."

    try {
      const response = await fetch(`${window.location.pathname}/batch_save_ari`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ updates: this.stagedChanges })
      })

      const result = await response.json()

      if (result.success) {
        this.stagedChanges = []
        this.clearStorage()
        window.location.reload()
      } else {
        alert(`Error: ${result.error}`)
        this.finalSyncButtonTarget.disabled = false
        this.finalSyncButtonTarget.textContent = "Confirm & Sync"
      }
    } catch (error) {
      alert("An unexpected error occurred during sync.")
      this.finalSyncButtonTarget.disabled = false
      this.finalSyncButtonTarget.textContent = "Confirm & Sync"
    }
  }

  syncRatePlans() {
    const selectedRoomTypeIds = this.roomTypeCheckboxTargets
      .filter(cb => cb.checked)
      .map(cb => cb.value)

    this.ratePlanOptionTargets.forEach(option => {
      const roomTypeId = option.dataset.roomTypeId
      const isVisible = selectedRoomTypeIds.includes(roomTypeId)
      
      option.classList.toggle("hidden", !isVisible)
      
      if (!isVisible) {
        const cb = option.querySelector('input[type="checkbox"]')
        if (cb) cb.checked = false
      }
    })
  }

  setMode(mode) {
    const normalizedMode = ["availability", "rates", "restrictions"].includes(mode) ? mode : "availability"
    if (this.hasModeTarget) this.modeTarget.value = normalizedMode
    
    this.applyInventoryTarget.checked = normalizedMode === "availability"
    this.applyRatesTarget.checked = normalizedMode === "rates"
    this.applyRestrictionsTarget.checked = normalizedMode === "restrictions"
    this.toggleSections()
  }

  currentMode() {
    return this.modeTarget.value || this.defaultModeValue || "availability"
  }

  toggleSections() {
    const inventoryEnabled = this.applyInventoryTarget.checked
    const ratesEnabled = this.applyRatesTarget.checked
    const restrictionsEnabled = this.applyRestrictionsTarget.checked

    this.inventoryFieldsTarget.classList.toggle("hidden", !inventoryEnabled)
    this.rateFieldsTarget.classList.toggle("hidden", !ratesEnabled)
    this.restrictionFieldsTarget.classList.toggle("hidden", !restrictionsEnabled)
    this.ratePlanFieldsTarget.classList.toggle("hidden", !(ratesEnabled || restrictionsEnabled))
  }

  filterRoomTypes() {
    if (!this.hasRoomTypeSearchTarget) return
    const query = this.roomTypeSearchTarget.value.toLowerCase()
    
    this.roomTypeOptionTargets.forEach(option => {
      const match = option.dataset.searchText.includes(query)
      option.classList.toggle("hidden", !match)
    })
  }

  filterRatePlans() {
    if (!this.hasRatePlanSearchTarget) return
    const query = this.ratePlanSearchTarget.value.toLowerCase()

    this.ratePlanOptionTargets.forEach(option => {
      const match = option.dataset.searchText.includes(query)
      option.classList.toggle("hidden", !match)
    })
  }

  selectAllRoomTypes(event) {
    if (event) event.preventDefault()
    this.roomTypeCheckboxTargets.forEach(cb => {
      const option = cb.closest("[data-inventory-calendar-target='roomTypeOption']")
      if (option && !option.classList.contains("hidden")) {
        cb.checked = true
      }
    })
    this.syncRatePlans()
  }

  clearRoomTypes(event) {
    if (event) event.preventDefault()
    this.roomTypeCheckboxTargets.forEach(cb => cb.checked = false)
    this.syncRatePlans()
  }

  selectAllRatePlans(event) {
    if (event) event.preventDefault()
    this.ratePlanCheckboxTargets.forEach(cb => {
      const option = cb.closest("[data-inventory-calendar-target='ratePlanOption']")
      if (option && !option.classList.contains("hidden")) {
        cb.checked = true
      }
    })
  }

  clearRatePlans(event) {
    if (event) event.preventDefault()
    this.ratePlanCheckboxTargets.forEach(cb => cb.checked = false)
  }

  resetForm() {
    this.skipConfirm = false
    this.startDateTarget.value = this.defaultStartValue
    this.endDateTarget.value = this.defaultEndValue
    this.roomTypeCheckboxTargets.forEach(cb => cb.checked = true)
    this.ratePlanCheckboxTargets.forEach(cb => cb.checked = true)
    if (this.hasRoomTypeSearchTarget) this.roomTypeSearchTarget.value = ""
    if (this.hasRatePlanSearchTarget) this.ratePlanSearchTarget.value = ""
    this.filterRoomTypes()
    this.filterRatePlans()
    this.syncRatePlans()
    this.quantityFieldTarget.value = ""
    this.statusFieldTarget.value = ""
    this.priceFieldTarget.value = ""
    
    // Reset searchable currency select
    const currency = this.defaultCurrencyValue || "MYR"
    this.currencyFieldTarget.value = currency
    const searchableSelect = this.currencyFieldTarget.closest('[data-controller="searchable-select"]')
    if (searchableSelect) {
      const input = searchableSelect.querySelector('[data-searchable-select-target="input"]')
      const option = searchableSelect.querySelector(`[data-value="${currency}"]`)
      if (input && option) input.value = option.dataset.label
    }

    this.minStayFieldTarget.value = ""
    this.maxStayFieldTarget.value = ""
    this.ctaFieldTarget.checked = false
    this.ctdFieldTarget.checked = false
    this.stopSellFieldTarget.checked = false
    this.applyInventoryTarget.checked = false
    this.applyRatesTarget.checked = false
    this.applyRestrictionsTarget.checked = false
    this.toggleSections()
  }

  openDialog() {
    if (typeof this.dialogTarget.showModal === "function") {
      this.dialogTarget.showModal()
    } else {
      this.dialogTarget.setAttribute("open", "open")
    }
  }

  titleForMode(mode) {
    if (mode === "rates") return "Update Rates"
    if (mode === "restrictions") return "Update Restrictions"
    return "Update Availability"
  }
}
