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
    "currentQuantityHint",
    "currentStatusHint",
    "priceField",
    "priceLabel",
    "baseOccupancyField",
    "extraPaxChargeField",
    "singleSupplementField",
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
    "finalSyncButton",
    "navStartDate",
    "navRoomType",
    "successDialog",
    "info",
    "channelIdField",
    "channelRatePlanIdField",
    "paxFields"
  ]

  static values = {
    hotelId: String,
    batchUrl: String,
    defaultMode: String,
    defaultStart: String,
    defaultEnd: String,
    defaultCurrency: String,
    baseCurrency: String,
    allowPaxPricing: Boolean
  }

  initialize() {
    this.stagedChanges = []
    this.initialValues = {}
    this.touchedFields = new Set()
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

    // Re-apply highlights when Turbo Frame reloads
    const frame = document.getElementById("inventory_calendar_frame")
    if (frame) {
      this.reapplyHighlightsHandler = () => {
        this.stagedChanges.forEach(change => this.highlightStagedCells(change))
        
        // Synchronized direct jump to top if anchor is in URL or success message is visible
        const hasTopAnchor = window.location.href.includes("#top")
        const hasFlashMessage = frame.querySelector('[data-controller="toast"]')
        
        if (hasTopAnchor || hasFlashMessage) {
          this.scrollToTop()
        }
      }
      frame.addEventListener("turbo:frame-load", this.reapplyHighlightsHandler)
    }

    // Close any open tooltips when clicking outside
    this.closeAllTooltipsHandler = (e) => {
      if (!e.target.closest('[data-tooltip-id]')) {
        document.querySelectorAll('[id$="-tip"]').forEach(t => {
          t.classList.add("hidden", "opacity-0", "scale-95")
          t.classList.remove("opacity-100", "scale-100")
        })
      }
    }
    document.addEventListener("click", this.closeAllTooltipsHandler)
  }

  disconnect() {
    const frame = document.getElementById("inventory_calendar_frame")
    if (frame && this.reapplyHighlightsHandler) {
      frame.removeEventListener("turbo:frame-load", this.reapplyHighlightsHandler)
    }
    if (this.closeAllTooltipsHandler) {
      document.removeEventListener("click", this.closeAllTooltipsHandler)
    }
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
    this.touchedFields.clear()
    this.titleTarget.textContent = "Bulk Edit"
    this.subtitleTarget.textContent = "Updates will be detected automatically as you change fields."
    this.submitButtonTarget.value = "Stage Changes"
    if (this.hasCurrentStatusHintTarget) this.currentStatusHintTarget.textContent = ""
    
    // In bulk mode, we treat all fields as 'empty' initially
    this.initialValues = {
      quantity: "", status: "", price: "", 
      base_occupancy: "", extra_pax_charge: "", single_supplement: "",
      min_stay: "", max_stay: "", 
      closed_to_arrival: false, closed_to_departure: false, stop_sell: false
    }

    this.openDialog()
  }

  openCell(event) {
    const data = event.currentTarget.dataset

    this.resetForm()
    this.touchedFields.clear()
    
    // Set channel-specific fields if present
    if (this.hasChannelIdFieldTarget) {
      this.channelIdFieldTarget.value = data.channelId || ""
    }
    if (this.hasChannelRatePlanIdFieldTarget) {
      this.channelRatePlanIdFieldTarget.value = data.channelRatePlanId || ""
    }
    this.activeChannelName = data.channelName || ""

    // Set mode based on data attribute (rates, availability, etc.)
    let mode = data.mode
    if (mode === "channel_availability") {
      mode = "availability"
    } else if (mode === "channel_rates" || mode === "rates") {
      mode = "combined"
    } else {
      mode = mode || this.currentMode()
    }
    this.setMode(mode)
    
    this.startDateTarget.value = data.date
    this.endDateTarget.value = data.date
    
    // Select the specific room type
    this.roomTypeCheckboxTargets.forEach(cb => {
      cb.checked = (cb.value === data.roomTypeId)
      if (data.channelId) {
        cb.disabled = (cb.value !== data.roomTypeId)
      } else {
        cb.disabled = false
      }
    })

    this.syncRatePlans()

    // Select the specific rate plan OR virtual tier checkbox
    if (data.ratePlanId) {
      this.ratePlanCheckboxTargets.forEach(cb => {
        cb.checked = (cb.value === data.ratePlanId)
        if (data.channelId) {
          cb.disabled = (cb.value !== data.ratePlanId)
        } else {
          cb.disabled = false
        }
      })
    } else {
      if (data.mode === "channel_availability") {
        this.ratePlanCheckboxTargets.forEach(cb => {
          cb.checked = false
          cb.disabled = true
        })
      } else {
        this.ratePlanCheckboxTargets.forEach(cb => {
          cb.disabled = false
        })
      }
    }

    if (data.mode === "channel_availability" || data.mode === "availability") {
      this.quantityFieldTarget.value = data.quantity || ""
      this.statusFieldTarget.value = ""
      
      const current = data.status || "open"
      if (this.hasCurrentStatusHintTarget) this.currentStatusHintTarget.textContent = `Currently: ${current.toUpperCase()}`
      if (this.hasCurrentQuantityHintTarget) this.currentQuantityHintTarget.textContent = `Current: ${data.quantity || 0}`
    } else {
      if (this.hasCurrentStatusHintTarget) this.currentStatusHintTarget.textContent = ""
      if (this.hasCurrentQuantityHintTarget) this.currentQuantityHintTarget.textContent = ""
      this.priceFieldTarget.value = data.price || ""
      if (this.hasBaseOccupancyFieldTarget) this.baseOccupancyFieldTarget.value = data.baseOccupancy || ""
      if (this.hasExtraPaxChargeFieldTarget) this.extraPaxChargeFieldTarget.value = data.extraPaxCharge || ""
      if (this.hasSingleSupplementFieldTarget) this.singleSupplementFieldTarget.value = data.singleSupplement || ""
      
      const currency = data.currency || this.baseCurrencyValue || this.defaultCurrencyValue || "MYR"
      this.syncCurrencySelect(currency)

      this.minStayFieldTarget.value = data.minStay || ""
      this.maxStayFieldTarget.value = data.maxStay || ""
      this.ctaFieldTarget.checked = data.closedToArrival === "true"
      this.ctdFieldTarget.checked = data.closedToDeparture === "true"
      this.stopSellFieldTarget.checked = data.stopSell === "true"
    }

    if (data.channelName) {
      this.titleTarget.textContent = `Update ${data.channelName}`
    } else {
      this.titleTarget.textContent = this.titleForMode(data.mode || this.currentMode())
    }
    this.subtitleTarget.textContent = `Staging update for ${data.date}`
    this.submitButtonTarget.value = "Stage Update"

    // Capture initial values for automatic change detection
    this.initialValues = this.getFormValues()

    this.openDialog()
  }

  getFormValues() {
    return {
      quantity: this.quantityFieldTarget.value,
      status: this.statusFieldTarget.value,
      price: this.priceFieldTarget.value,
      base_occupancy: this.hasBaseOccupancyFieldTarget ? this.baseOccupancyFieldTarget.value : "",
      extra_pax_charge: this.hasExtraPaxChargeFieldTarget ? this.extraPaxChargeFieldTarget.value : "",
      single_supplement: this.hasSingleSupplementFieldTarget ? this.singleSupplementFieldTarget.value : "",
      min_stay: this.minStayFieldTarget.value,
      max_stay: this.maxStayFieldTarget.value,
      closed_to_arrival: this.ctaFieldTarget.checked,
      closed_to_departure: this.ctdFieldTarget.checked,
      stop_sell: this.stopSellFieldTarget.checked
    }
  }

  toggleInfo(event) {
    if (event) event.preventDefault()
    const infoId = event.currentTarget.dataset.infoId
    const infoBox = this.infoTargets.find(el => el.dataset.infoId === infoId)
    if (infoBox) {
      infoBox.classList.toggle("hidden")
    }
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
    
    const currentValues = this.getFormValues()
    const modifiedFields = []
    
    // Automatic field change detection + Touched detection
    Object.keys(currentValues).forEach(key => {
      const current = currentValues[key]
      const initial = this.initialValues[key]
      
      // If user touched/clicked/typed in the field, count it!
      if (this.touchedFields.has(key)) {
        modifiedFields.push(key)
        return
      }

      // For bulk mode, if field is not empty, it's considered a change
      const isBulk = this.titleTarget.textContent === "Bulk Edit"
      
      if (isBulk) {
        if (current !== "" && current !== false) modifiedFields.push(key)
      } else {
        // Single cell: check for actual diff
        // We use string conversion for numbers to be safe
        if (current.toString() !== initial.toString()) {
          modifiedFields.push(key)
        }
      }
    })

    if (modifiedFields.length === 0) {
      alert("No changes detected. Please update at least one field.")
      return
    }

    const applyInventory = modifiedFields.some(f => ["quantity", "status"].includes(f))
    const applyRates = modifiedFields.some(f => ["price", "base_occupancy", "extra_pax_charge", "single_supplement"].includes(f))
    const applyRestrictions = modifiedFields.some(f => ["min_stay", "max_stay", "closed_to_arrival", "closed_to_departure", "stop_sell"].includes(f))

    const channelId = this.hasChannelIdFieldTarget ? this.channelIdFieldTarget.value : ""
    const channelRatePlanId = this.hasChannelRatePlanIdFieldTarget ? this.channelRatePlanIdFieldTarget.value : ""

    const change = {
      id: Math.random().toString(36).substr(2, 9),
      start_date: this.startDateTarget.value,
      end_date: this.endDateTarget.value,
      room_type_ids: selectedRoomTypes.map(rt => rt.id),
      rate_plan_ids: selectedRatePlans.map(rp => rp.id),
      apply_inventory: applyInventory,
      apply_rates: applyRates,
      apply_restrictions: applyRestrictions,
      modified_fields: modifiedFields,
      quantity: currentValues.quantity,
      status: currentValues.status,
      price: currentValues.price,
      base_occupancy: currentValues.base_occupancy,
      extra_pax_charge: currentValues.extra_pax_charge,
      single_supplement: currentValues.single_supplement,
      currency: this.baseCurrencyValue || this.defaultCurrencyValue || "MYR",
      min_stay: currentValues.min_stay,
      max_stay: currentValues.max_stay,
      closed_to_arrival: currentValues.closed_to_arrival,
      closed_to_departure: currentValues.closed_to_departure,
      stop_sell: currentValues.stop_sell,
      channel_id: channelId,
      channel_rate_plan_id: channelRatePlanId,
      channel_name: this.activeChannelName || "",
      summary: this.buildSummary(selectedRoomTypes, selectedRatePlans, modifiedFields, currentValues)
    }

    this.stagedChanges.push(change)
    this.saveStagedChanges()
    this.updateSyncButton()
    this.highlightStagedCells(change)
  }

  buildSummary(selectedRoomTypes, selectedRatePlans, modifiedFields, values) {
    const actions = []
    const details = []
    
    if (modifiedFields.some(f => ["quantity", "status"].includes(f))) {
      actions.push("Inventory")
      const invParts = []
      if (modifiedFields.includes("quantity") && values.quantity !== "") invParts.push(`Qty: ${values.quantity}`)
      if (modifiedFields.includes("status") && values.status !== "") invParts.push(`Status: ${values.status}`)
      if (invParts.length > 0) details.push(invParts.join(", "))
    }
    
    const rateModified = modifiedFields.some(f => ["price", "base_occupancy", "extra_pax_charge", "single_supplement"].includes(f))
    if (rateModified) {
      actions.push("Rates")
      const rateParts = []
      if (modifiedFields.includes("price") && values.price !== "") {
        rateParts.push(`Price: ${this.baseCurrencyValue || "MYR"} ${values.price}`)
      }
      if (modifiedFields.includes("base_occupancy") && values.base_occupancy !== "") {
        rateParts.push(`Base Occ: ${values.base_occupancy}`)
      }
      if (modifiedFields.includes("extra_pax_charge") && values.extra_pax_charge !== "") {
        rateParts.push(`Extra Pax: ${this.baseCurrencyValue || "MYR"} ${values.extra_pax_charge}`)
      }
      if (modifiedFields.includes("single_supplement") && values.single_supplement !== "") {
        rateParts.push(`Single Supp: ${this.baseCurrencyValue || "MYR"} ${values.single_supplement}`)
      }
      if (rateParts.length > 0) details.push(rateParts.join(", "))
    }
    
    if (modifiedFields.some(f => ["min_stay", "max_stay", "closed_to_arrival", "closed_to_departure", "stop_sell"].includes(f))) {
      const restr = []
      if (modifiedFields.includes("min_stay") && values.min_stay) restr.push(`Min Stay: ${values.min_stay}`)
      if (modifiedFields.includes("max_stay") && values.max_stay) restr.push(`Max Stay: ${values.max_stay}`)
      if (modifiedFields.includes("closed_to_arrival")) restr.push(values.closed_to_arrival ? "CTA: ON" : "CTA: OFF")
      if (modifiedFields.includes("closed_to_departure")) restr.push(values.closed_to_departure ? "CTD: ON" : "CTD: OFF")
      if (modifiedFields.includes("stop_sell")) restr.push(values.stop_sell ? "Stop Sell: ON" : "Stop Sell: OFF")
      
      if (restr.length > 0) {
        actions.push("Restrictions")
        details.push(restr.join(", "))
      }
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
        if (change.channel_id) {
          if (change.apply_inventory) {
            this.markCellDirty(`channel-availability-cell-${roomTypeId}-${change.channel_id}-${date}`, {
              quantity: change.quantity,
              status: change.status,
              currency: change.currency
            })
          } else {
            change.rate_plan_ids.forEach(ratePlanId => {
              this.markCellDirty(`channel-rate-cell-${roomTypeId}-${ratePlanId}-${change.channel_rate_plan_id}-${date}`, {
                price: change.apply_rates ? change.price : undefined,
                base_occupancy: change.apply_rates ? change.base_occupancy : undefined,
                extra_pax_charge: change.apply_rates ? change.extra_pax_charge : undefined,
                single_supplement: change.apply_rates ? change.single_supplement : undefined,
                currency: change.currency,
                min_stay: change.apply_restrictions ? change.min_stay : undefined,
                max_stay: change.apply_restrictions ? change.max_stay : undefined,
                closed_to_arrival: change.apply_restrictions ? change.closed_to_arrival : undefined,
                closed_to_departure: change.apply_restrictions ? change.closed_to_departure : undefined,
                stop_sell: change.apply_restrictions ? change.stop_sell : undefined
              })
            })
          }
        } else {
          if (change.apply_inventory) {
            this.markCellDirty(`availability-cell-${roomTypeId}-${date}`, {
              quantity: change.quantity,
              status: change.status
            })
          }

          if (change.apply_rates || change.apply_restrictions) {
            change.rate_plan_ids.forEach(ratePlanId => {
              let testid = `rate-cell-${roomTypeId}-${ratePlanId}-${date}`

              // Handle virtual tiers (e.g. tier_walk_in_123)
              if (typeof ratePlanId === 'string' && ratePlanId.startsWith('tier_')) {
                const tierName = ratePlanId.split('_')[1].replace('_', '-')
                testid = `${tierName}-cell-${roomTypeId}-${date}`
              }

              this.markCellDirty(testid, {
                price: change.apply_rates ? change.price : undefined,
                base_occupancy: change.apply_rates ? change.base_occupancy : undefined,
                extra_pax_charge: change.apply_rates ? change.extra_pax_charge : undefined,
                single_supplement: change.apply_rates ? change.single_supplement : undefined,
                currency: change.currency,
                min_stay: change.apply_restrictions ? change.min_stay : undefined,
                max_stay: change.apply_restrictions ? change.max_stay : undefined,
                closed_to_arrival: change.apply_restrictions ? change.closed_to_arrival : undefined,
                closed_to_departure: change.apply_restrictions ? change.closed_to_departure : undefined,
                stop_sell: change.apply_restrictions ? change.stop_sell : undefined
              })
            })
          }
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
        if (data.quantity !== undefined && data.quantity !== "") {
          cell.dataset.quantity = data.quantity
          // Update visual availability count
          const qtySpan = cell.querySelector(".font-black")
          if (qtySpan) qtySpan.textContent = data.quantity
        }
        if (data.status !== undefined && data.status !== "") {
          cell.dataset.status = data.status
          // Update status label ("Open" or "Blocked")
          const statusSpan = cell.querySelector(".uppercase")
          if (statusSpan) {
            statusSpan.textContent = data.status === "closed" ? "Blocked" : "Open"
            statusSpan.classList.toggle("text-rose-600", data.status === "closed")
            statusSpan.classList.toggle("text-emerald-600", data.status !== "closed")
          }
        }
        if (data.price !== undefined && data.price !== "") {
          cell.dataset.price = data.price

          // Update visual price display
          const priceSpan = cell.querySelector(".tabular-nums")
          if (priceSpan) {
            let symbol = data.currency
            if (data.currency === "USD") symbol = "$"
            else if (data.currency === "MYR") symbol = "RM"
            else if (data.currency === "GBP") symbol = "£"
            else if (data.currency === "EUR") symbol = "€"
            else if (data.currency === "JPY") symbol = "¥"

            const formatted = parseFloat(data.price).toLocaleString(undefined, {
              minimumFractionDigits: 0,
              maximumFractionDigits: 2
            })
            priceSpan.textContent = `${symbol}${formatted}`

            // For channel rates, apply bold indigo coloring if modified
            priceSpan.classList.remove("text-slate-500")
            priceSpan.classList.add("text-indigo-600", "font-extrabold")
          }
        }
        if (data.min_stay !== undefined && data.min_stay !== "") cell.dataset.minStay = data.min_stay
        if (data.max_stay !== undefined && data.max_stay !== "") cell.dataset.maxStay = data.max_stay
        if (data.closed_to_arrival !== undefined) cell.dataset.closedToArrival = data.closed_to_arrival ? "true" : "false"
        if (data.closed_to_departure !== undefined) cell.dataset.closedToDeparture = data.closed_to_departure ? "true" : "false"
        if (data.stop_sell !== undefined) cell.dataset.stopSell = data.stop_sell ? "true" : "false"
        if (data.base_occupancy !== undefined && data.base_occupancy !== "") cell.dataset.baseOccupancy = data.base_occupancy
        if (data.extra_pax_charge !== undefined && data.extra_pax_charge !== "") cell.dataset.extraPaxCharge = data.extra_pax_charge
        if (data.single_supplement !== undefined && data.single_supplement !== "") cell.dataset.singleSupplement = data.single_supplement
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
      const actionBadge = change.channel_name 
        ? `${change.summary.actions} (${change.channel_name})`
        : change.summary.actions

      return `
        <div class="rounded-xl border border-indigo-100 bg-indigo-50/30 p-4 shadow-sm space-y-3">
          <div class="flex items-start justify-between">
            <div class="space-y-1">
              <div class="flex flex-wrap items-center gap-2">
                <span class="inline-flex items-center rounded-md bg-indigo-100 px-1.5 py-0.5 text-[10px] font-black uppercase tracking-wider text-indigo-700">${actionBadge}</span>
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
    
    // Re-render all highlights to reflect the current staged state
    this.clearAllHighlights()
    this.stagedChanges.forEach(change => this.highlightStagedCells(change))
    
    this.renderReviewList()
    this.updateSyncButton()
    if (this.stagedChanges.length === 0) {
      this.clearStorage()
      this.closeReview()
    }
  }

  async submitStaged(event) {
    if (event) event.preventDefault()
    
    this.finalSyncButtonTarget.disabled = true
    this.finalSyncButtonTarget.textContent = "Syncing..."

    try {
      const response = await fetch(this.batchUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ updates: this.stagedChanges })
      })

      if (!response.ok && response.status !== 422) {
        throw new Error(`Server returned ${response.status}: ${response.statusText}`)
      }

      const result = await response.json()

      if (result.success) {
        // 1. Clear everything locally for immediate real-time feedback
        this.stagedChanges = []
        this.clearStorage()
        this.updateSyncButton() // Immediately reset counter to 0
        this.clearAllHighlights() // Immediately remove dirty marks from cells
        this.closeReview() // Close the review modal
        
        // 2. Reset the final sync button state (it's outside the frame)
        this.finalSyncButtonTarget.disabled = false
        this.finalSyncButtonTarget.textContent = this.finalSyncButtonTarget.dataset.syncText || "Confirm & Sync"

        // 3. Reload the calendar table from the server
        const frame = document.getElementById("inventory_calendar_frame")
        if (frame) {
          const url = new URL(window.location.href)
          frame.src = url.toString()
          // Turbo frame src update automatically triggers a reload
        } else {
          window.location.reload()
        }

        // 4. Show success modal
        if (this.hasSuccessDialogTarget) {
          this.successDialogTarget.showModal()
        }
      } else {
        alert(`Error: ${result.error}`)
        this.finalSyncButtonTarget.disabled = false
        this.finalSyncButtonTarget.textContent = "Confirm & Sync"
      }
    } catch (error) {
      console.error("Sync Error:", error)
      alert(`An unexpected error occurred during sync: ${error.message}`)
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
    const normalizedMode = ["availability", "rates", "restrictions", "combined"].includes(mode) ? mode : "availability"
    if (this.hasModeTarget) this.modeTarget.value = normalizedMode
    
    if (normalizedMode === "availability") {
      this.applyInventoryTarget.value = "1"
      this.applyRatesTarget.value = "0"
      this.applyRestrictionsTarget.value = "0"
    } else if (normalizedMode === "rates") {
      this.applyInventoryTarget.value = "0"
      this.applyRatesTarget.value = "1"
      this.applyRestrictionsTarget.value = "0"
    } else if (normalizedMode === "restrictions") {
      this.applyInventoryTarget.value = "0"
      this.applyRatesTarget.value = "0"
      this.applyRestrictionsTarget.value = "1"
    } else if (normalizedMode === "combined") {
      this.applyInventoryTarget.value = "0"
      this.applyRatesTarget.value = "1"
      this.applyRestrictionsTarget.value = "1"
    }

    this.toggleSections()
  }

  currentMode() {
    return this.modeTarget.value || this.defaultModeValue || "availability"
  }

  toggleSections() {
    const mode = this.currentMode()
    const isChannelOverride = this.hasChannelIdFieldTarget && this.channelIdFieldTarget.value !== ""
    
    // In Combined or Rates mode, we show everything except Inventory
    // In Availability mode, we show only Inventory
    if (this.hasInventoryFieldsTarget) {
      this.inventoryFieldsTarget.classList.toggle("hidden", mode !== "availability")
    }
    
    if (this.hasRateFieldsTarget) {
      this.rateFieldsTarget.classList.toggle("hidden", mode === "availability")
    }
    
    if (this.hasRestrictionFieldsTarget) {
      this.restrictionFieldsTarget.classList.toggle("hidden", mode === "availability")
    }
    
    if (this.hasRatePlanFieldsTarget) {
      this.ratePlanFieldsTarget.classList.toggle("hidden", mode === "availability")
    }

    if (this.hasPaxFieldsTarget) {
      this.paxFieldsTarget.classList.toggle("hidden", mode === "availability" || isChannelOverride)
    }
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
    if (this.hasPriceLabelTarget) {
      this.priceLabelTarget.textContent = `Price (${this.baseCurrencyValue || "MYR"})`
    }
    if (this.hasBaseOccupancyFieldTarget) this.baseOccupancyFieldTarget.value = ""
    if (this.hasExtraPaxChargeFieldTarget) this.extraPaxChargeFieldTarget.value = ""
    if (this.hasSingleSupplementFieldTarget) this.singleSupplementFieldTarget.value = ""
    if (this.hasCurrentStatusHintTarget) this.currentStatusHintTarget.textContent = ""
    if (this.hasCurrentQuantityHintTarget) this.currentQuantityHintTarget.textContent = ""
    
    // Reset hidden fields
    if (this.hasCurrencyFieldTarget) {
      this.currencyFieldTarget.value = this.baseCurrencyValue || "MYR"
    }

    this.minStayFieldTarget.value = ""
    this.maxStayFieldTarget.value = ""
    this.ctaFieldTarget.checked = false
    this.ctdFieldTarget.checked = false
    this.stopSellFieldTarget.checked = false
    
    // Reset Tiered Logic
    if (this.hasRateTierFieldTarget) this.rateTierFieldTarget.value = ""
    if (this.hasMasterPlanStaticTarget) this.masterPlanStaticTarget.classList.add("hidden")

    this.toggleSections()
  }

  syncCurrencySelect(currency) {
    if (!this.hasCurrencyFieldTarget) return

    this.currencyFieldTarget.value = currency
    
    const searchableSelect = this.currencyFieldTarget.closest('[data-controller="searchable-select"]')
    if (searchableSelect) {
      const input = searchableSelect.querySelector('[data-searchable-select-target="input"]')
      const option = searchableSelect.querySelector(`[data-value="${currency}"]`)
      if (input) {
        input.value = option ? option.dataset.label : currency
      }
    }
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

  navigate(event) {
    if (event) event.preventDefault()

    const startDate = this.navStartDateTarget.value
    const roomTypeId = this.navRoomTypeTarget.value
    
    const url = new URL(window.location.href)
    url.searchParams.set("start_date", startDate)
    if (roomTypeId) {
      url.searchParams.set("room_type_id", roomTypeId)
    } else {
      url.searchParams.delete("room_type_id")
    }

    // Preserve tab state if present in current URL
    const currentParams = new URLSearchParams(window.location.search)
    if (currentParams.has("tab")) url.searchParams.set("tab", currentParams.get("tab"))
    if (currentParams.has("subtab")) url.searchParams.set("subtab", currentParams.get("subtab"))

    // Clear legacy multi-select params so "All room types" is not pinned by stale query state.
    url.searchParams.delete("room_type_ids")
    url.searchParams.delete("room_type_ids[]")

    const frame = document.getElementById("inventory_calendar_frame")
    if (frame) {
      frame.src = url.toString()
    } else {
      window.location.href = url.toString()
    }
  }

  closeSuccess(event) {
    if (event) event.preventDefault()
    this.successDialogTarget.close()
  }

  scrollToTop() {
    const topEl = document.getElementById("top")
    if (topEl) {
      topEl.scrollIntoView({ behavior: "auto" })
    } else {
      window.scrollTo({ top: 0, behavior: "auto" })
    }
  }

  markTouched(event) {
    const target = event.currentTarget
    const fieldName = target.name.split("[").pop().replace("]", "")
    this.touchedFields.add(fieldName)
  }

  showTooltip(event) {
    if (window.innerWidth < 1024) return
    const id = event.currentTarget.dataset.tooltipId
    const tip = document.getElementById(id)
    if (tip) {
      tip.classList.remove("hidden")
      void tip.offsetWidth
      tip.classList.remove("opacity-0", "scale-95")
      tip.classList.add("opacity-100", "scale-100")
    }
  }

  hideTooltip(event) {
    if (window.innerWidth < 1024) return
    const id = event.currentTarget.dataset.tooltipId
    const tip = document.getElementById(id)
    if (tip) {
      tip.classList.add("opacity-0", "scale-95")
      tip.classList.remove("opacity-100", "scale-100")
      setTimeout(() => {
        if (tip.classList.contains("opacity-0")) {
          tip.classList.add("hidden")
        }
      }, 200)
    }
  }

  toggleTooltip(event) {
    event.preventDefault()
    event.stopPropagation()
    const id = event.currentTarget.dataset.tooltipId
    const tip = document.getElementById(id)
    if (tip) {
      const isHidden = tip.classList.contains("hidden")
      
      // Close all other tooltips first
      document.querySelectorAll('[id$="-tip"]').forEach(t => {
        t.classList.add("hidden", "opacity-0", "scale-95")
        t.classList.remove("opacity-100", "scale-100")
      })

      if (isHidden) {
        tip.classList.remove("hidden")
        void tip.offsetWidth
        tip.classList.remove("opacity-0", "scale-95")
        tip.classList.add("opacity-100", "scale-100")
      }
    }
  }
}
