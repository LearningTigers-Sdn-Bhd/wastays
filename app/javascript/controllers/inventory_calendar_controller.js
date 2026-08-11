import { Controller } from "@hotwired/stimulus"
import { syncSelectMenu } from "controllers/panels_ui/select_menu_sync"

// Staged-change field name -> the Stimulus target holding it in the editor.
const FIELD_TARGETS = {
  quantity: "quantityField",
  status: "statusField",
  price: "priceField",
  base_occupancy: "baseOccupancyField",
  extra_pax_charge: "extraPaxChargeField",
  single_supplement: "singleSupplementField",
  min_stay: "minStayField",
  max_stay: "maxStayField",
  closed_to_arrival: "ctaField",
  closed_to_departure: "ctdField",
  stop_sell: "stopSellField"
}

export default class extends Controller {
  // The cell editor is server-rendered into #inventory_selection_sheet, so every
  // form target below is absent until that frame loads and gone again once the
  // sheet closes. Read them through the `has…Target` guards, never directly.
  static targets = [
    "form",
    "mode",
    "applyInventory",
    "applyRates",
    "applyRestrictions",
    "quantityField",
    "statusField",
    "priceField",
    "baseOccupancyField",
    "extraPaxChargeField",
    "singleSupplementField",
    "occupancyPriceField",
    "occupancyPriceRow",
    "currencyField",
    "minStayField",
    "maxStayField",
    "ctaField",
    "ctdField",
    "stopSellField",
    "submitButton",
    "syncButton",
    "syncCounter",
    "syncHeader",
    "reviewDialog",
    "reviewList",
    "finalSyncButton",
    "navStartDate",
    "navMonth",
    "navRoomType",
    "successDialog",
    "channelIdField",
    "channelRatePlanIdField",
    "paxFields",
    "otasToggleCheckbox",
    "topPanel",
    "fullscreenRestoreBtn",
    "lockTip"
  ]

  static values = {
    hotelId: String,
    batchUrl: String,
    occupancyDetailsUrl: String,
    defaultMode: String,
    defaultStart: String,
    defaultEnd: String,
    defaultCurrency: String,
    chargingModel: String,
    baseCurrency: String
  }

  initialize() {
    this.stagedChanges = []
    this.initialValues = {}
    this.initialFormSnapshot = ""
    this.touchedFields = new Set()
  }

  connect() {
    this.skipConfirm = false
    this.loadStagedChanges()
    this.updateSyncButton()

    // The editor arrives over Turbo. Capture its pristine values then, so the
    // staging step can tell an edited field from an untouched one, and replay
    // any change already staged for this cell over the server's saved values.
    this.sheetFrame = document.getElementById("inventory_selection_sheet")
    if (this.sheetFrame) {
      this.sheetLoadHandler = () => {
        if (!this.hasFormTarget) return
        this.touchedFields.clear()
        this.applyStagedValuesToForm()
        this.initialValues = this.getFormValues()
        this.initialFormSnapshot = this.formSnapshot()
      }
      this.sheetFrame.addEventListener("turbo:frame-load", this.sheetLoadHandler)
    }

    // Restore OTAs mode
    const storedOtasMode = localStorage.getItem(`ari_otas_mode_${this.hotelIdValue}`) || "hidden"
    this.updateOtasMode(storedOtasMode)

    // Re-apply highlights when Turbo Frame reloads
    const frame = document.getElementById("inventory_calendar_frame")
    if (frame) {
      this.reapplyHighlightsHandler = () => {
        this.stagedChanges.forEach(change => this.highlightStagedCells(change))
        
        // Synchronized direct jump to top if anchor is in URL or success message is visible
        const hasTopAnchor = window.location.href.includes("#top")
        if (hasTopAnchor) {
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

  // A second disconnect() further down used to shadow this one, so neither the
  // frame listener nor the document listener was ever removed. Both cleanups
  // live here now.
  disconnect() {
    const frame = document.getElementById("inventory_calendar_frame")
    if (frame && this.reapplyHighlightsHandler) {
      frame.removeEventListener("turbo:frame-load", this.reapplyHighlightsHandler)
    }
    if (this.sheetFrame && this.sheetLoadHandler) {
      this.sheetFrame.removeEventListener("turbo:frame-load", this.sheetLoadHandler)
    }
    if (this.closeAllTooltipsHandler) {
      document.removeEventListener("click", this.closeAllTooltipsHandler)
    }
    document.body.classList.remove("hotel-portal-focus-mode")
  }

  toggleOtas(event) {
    const checked = event.currentTarget.checked
    const mode = checked ? "expanded" : "hidden"
    this.updateOtasMode(mode)
  }

  updateOtasMode(mode) {
    if (mode !== "hidden") {
      mode = "expanded"
    }
    this.otasMode = mode
    localStorage.setItem(`ari_otas_mode_${this.hotelIdValue}`, mode)

    const grid = this.element.querySelector('[data-testid="inventory-calendar-grid"]')
    if (grid) {
      grid.setAttribute('data-otas-mode', mode)
    }

    if (this.hasOtasToggleCheckboxTarget) {
      this.otasToggleCheckboxTarget.checked = (mode === "expanded")
    }
  }

  openOccupancyDetails(event) {
    if (event) event.preventDefault()
    const date = event.currentTarget.dataset.date
    const dialog = document.getElementById("occupancy-details-dialog")
    const frame = document.getElementById("occupancy_details_frame")
    if (dialog && frame && this.hasOccupancyDetailsUrlValue) {
      frame.src = `${this.occupancyDetailsUrlValue}?date=${date}`
      dialog.showModal()
    }
  }

  toggleFullscreen() {
    const isFocused = document.body.classList.toggle("hotel-portal-focus-mode")
    this.element.classList.toggle("focus-mode", isFocused)
    
    this.topPanelTargets.forEach(el => {
      el.classList.toggle("hidden", isFocused)
    })

    if (this.hasFullscreenRestoreBtnTarget) {
      this.fullscreenRestoreBtnTarget.classList.toggle("hidden", !isFocused)
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


  // The editor renders only the fields its mode needs, so every read is guarded.
  getFormValues() {
    return {
      quantity: this.fieldValue("quantityField"),
      status: this.fieldValue("statusField"),
      price: this.fieldValue("priceField"),
      base_occupancy: this.fieldValue("baseOccupancyField"),
      extra_pax_charge: this.fieldValue("extraPaxChargeField"),
      single_supplement: this.fieldValue("singleSupplementField"),
      occupancy_prices: this.occupancyPricesFromForm(),
      min_stay: this.fieldValue("minStayField"),
      max_stay: this.fieldValue("maxStayField"),
      closed_to_arrival: this.fieldChecked("ctaField"),
      closed_to_departure: this.fieldChecked("ctdField"),
      stop_sell: this.fieldChecked("stopSellField")
    }
  }

  fieldValue(name) {
    const capitalized = name.charAt(0).toUpperCase() + name.slice(1)
    return this[`has${capitalized}Target`] ? this[`${name}Target`].value : ""
  }

  // MultiSelect enhances a native <select multiple> that stays the source of
  // truth for the form post, so the staged summary reads the same element.
  // Its data attributes land on the component's wrapper, not the select, so
  // find it by the parameter name it submits under.
  selectedOptions(param) {
    const select = this.hasFormTarget &&
      this.formTarget.querySelector(`select[name="selection_update[${param}][]"]`)
    if (!select) return []

    return Array.from(select.selectedOptions).map(option => ({
      id: option.value,
      name: option.textContent.trim()
    }))
  }

  // DatePicker and MultiSelect both put caller-supplied data attributes on their
  // wrapper rather than on the control, so these are found by submitted name.
  formInput(param) {
    if (!this.hasFormTarget) return null

    return this.formTarget.querySelector(`[name="selection_update[${param}]"]`)
  }

  formInputValue(param) {
    return this.formInput(param)?.value || ""
  }

  fieldChecked(name) {
    const capitalized = name.charAt(0).toUpperCase() + name.slice(1)
    return this[`has${capitalized}Target`] ? this[`${name}Target`].checked : false
  }

  // Reopening a cell shows what the server has saved. A change staged earlier in
  // this session is not saved yet, so replay it over the form — otherwise the
  // editor would silently offer to overwrite the draft with the old values.
  applyStagedValuesToForm() {
    if (!this.hasFormTarget) return

    const { roomTypeId, ratePlanId, date } = this.formTarget.dataset
    const staged = this.stagedChanges.filter(change =>
      change.room_type_ids.map(String).includes(String(roomTypeId)) &&
      (!ratePlanId || change.rate_plan_ids.map(String).includes(String(ratePlanId))) &&
      change.start_date <= date && date <= change.end_date
    )
    if (staged.length === 0) return

    // Later stages win, matching the order the batch endpoint applies them in.
    staged.forEach(change => {
      change.modified_fields.forEach(field => {
        if (field === "occupancy_prices") {
          this.occupancyPriceFieldTargets.forEach(input => {
            const staged = change.occupancy_prices?.[input.dataset.adults]
            if (staged !== undefined) input.value = staged
          })
          return
        }

        const targetName = FIELD_TARGETS[field]
        const capitalized = targetName && targetName.charAt(0).toUpperCase() + targetName.slice(1)
        if (!targetName || !this[`has${capitalized}Target`]) return

        const input = this[`${targetName}Target`]
        if (input.type === "checkbox") {
          input.checked = Boolean(change[field])
        } else {
          input.value = change[field] ?? ""
        }
      })
    })
  }

  closeSheet() {
    const dialog = this.sheetFrame?.querySelector("dialog")
    if (!dialog) return

    const sheet = this.application.getControllerForElementAndIdentifier(dialog, "panels-ui--sheet")
    if (sheet) sheet.close()
    else dialog.close()
  }

  confirmSubmit(event) {
    // Submitting stages the change locally; nothing is written until Sync.
    event.preventDefault()
    if (this.stageCurrentSelection()) this.closeSheet()
    this.skipConfirm = false
  }

  stageCurrentSelection() {
    const selectedRoomTypes = this.fixedRoomTypeScope()
    const selectedRatePlans = this.selectedOptions("rate_plan_ids")

    const currentValues = this.getFormValues()
    const modifiedFields = []

    // A field counts as modified when the operator touched it, or when its value
    // differs from what the server rendered.
    Object.keys(currentValues).forEach(key => {
      if (this.touchedFields.has(key)) {
        modifiedFields.push(key)
        return
      }

      if (JSON.stringify(currentValues[key]) !== JSON.stringify(this.initialValues[key])) {
        modifiedFields.push(key)
      }
    })

    if (modifiedFields.length === 0) {
      alert("No changes detected. Please update at least one field.")
      return false
    }

    const applyInventory = modifiedFields.some(f => ["quantity", "status"].includes(f))
    const applyRates = modifiedFields.some(f => ["price", "base_occupancy", "extra_pax_charge", "single_supplement", "occupancy_prices"].includes(f))
    const applyRestrictions = modifiedFields.some(f => ["min_stay", "max_stay", "closed_to_arrival", "closed_to_departure", "stop_sell"].includes(f))

    if ((applyRates || applyRestrictions) && selectedRatePlans.length === 0) {
      alert("Select at least one rate plan to update.")
      return false
    }

    const channelId = this.hasChannelIdFieldTarget ? this.channelIdFieldTarget.value : ""
    const channelRatePlanId = this.hasChannelRatePlanIdFieldTarget ? this.channelRatePlanIdFieldTarget.value : ""

    const change = {
      id: Math.random().toString(36).substr(2, 9),
      start_date: this.formInputValue("start_date"),
      end_date: this.formInputValue("end_date"),
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
      occupancy_prices: currentValues.occupancy_prices,
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
    return true
  }

  fixedRoomTypeScope() {
    if (!this.hasFormTarget) return []

    const { roomTypeId, roomTypeName } = this.formTarget.dataset
    if (!roomTypeId) return []

    return [{ id: roomTypeId, name: roomTypeName || "Room category" }]
  }

  switchRoomType(event) {
    if (!this.hasFormTarget) return

    const select = event.target.closest("select")
    const roomTypeId = select?.value
    if (!roomTypeId || !this.formTarget.dataset.contextUrl) return

    if (this.formSnapshot() !== this.initialFormSnapshot && !window.confirm("Switch room categories and discard the unstaged changes in this sheet?")) {
      this.restoreRoomTypeContext(select)
      return
    }

    const destination = new URL(this.formTarget.dataset.contextUrl, window.location.origin)
    destination.searchParams.set("room_type_id", roomTypeId)
    destination.searchParams.delete("rate_plan_id")

    if (this.sheetFrame) this.sheetFrame.src = destination.toString()
  }

  formSnapshot() {
    if (!this.hasFormTarget) return ""

    return Array.from(new FormData(this.formTarget).entries())
      .filter(([key]) => key !== "selection_update[room_type_context_id]")
      .map(([key, value]) => `${key}=${value instanceof File ? `${value.name}:${value.size}` : value}`)
      .sort()
      .join("&")
  }

  restoreRoomTypeContext(select) {
    select.value = this.formTarget.dataset.roomTypeId
    syncSelectMenu(this.application, select)
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
    
    const rateModified = modifiedFields.some(f => ["price", "base_occupancy", "extra_pax_charge", "single_supplement", "occupancy_prices"].includes(f))
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
      if (modifiedFields.includes("occupancy_prices")) {
        Object.entries(values.occupancy_prices).forEach(([adults, amount]) => {
          rateParts.push(`${adults} adult${adults === "1" ? "" : "s"}: ${this.baseCurrencyValue || "MYR"} ${amount}`)
        })
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
    
    const start = this.formatDate(this.formInputValue("start_date"))
    const end = this.formatDate(this.formInputValue("end_date"))
    const dates = this.formInputValue("start_date") === this.formInputValue("end_date") 
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
    if (this.hasSyncHeaderTarget) {
      this.syncHeaderTarget.classList.toggle("hidden", count === 0)
    }
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
                occupancy_prices: change.apply_rates ? change.occupancy_prices : undefined,
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

              this.markCellDirty(testid, {
                price: change.apply_rates ? change.price : undefined,
                base_occupancy: change.apply_rates ? change.base_occupancy : undefined,
                extra_pax_charge: change.apply_rates ? change.extra_pax_charge : undefined,
                single_supplement: change.apply_rates ? change.single_supplement : undefined,
                occupancy_prices: change.apply_rates ? change.occupancy_prices : undefined,
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
      cell.classList.add("bg-indigo-50/70", "font-semibold")
      
      const priceSpan = cell.querySelector(".tabular-nums") || cell.querySelector("span")
      if (priceSpan) {
        priceSpan.classList.add("text-indigo-700", "font-extrabold")
      }

      // Add an absolute dot on top-right
      let dot = cell.querySelector(".dirty-dot")
      if (!dot) {
        dot = document.createElement("span")
        dot.className = "dirty-dot absolute top-1 right-1 h-1.5 w-1.5 rounded-full bg-indigo-500"
        cell.appendChild(dot)
      }
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
        if (data.occupancy_prices && Object.keys(data.occupancy_prices).length > 0) {
          cell.dataset.occupancyPrices = JSON.stringify(data.occupancy_prices)
          const displayPrice = data.occupancy_prices[cell.dataset.maxAdults]
          if (displayPrice !== undefined) cell.dataset.price = displayPrice
        }
      }
    }
  }

  clearAllHighlights() {
    this.element.querySelectorAll(".bg-indigo-50\\/70").forEach(cell => {
      cell.classList.remove("bg-indigo-50/70", "font-semibold")
      const priceSpan = cell.querySelector(".tabular-nums") || cell.querySelector("span")
      if (priceSpan) {
        priceSpan.classList.remove("text-indigo-700", "font-extrabold")
      }
      const dot = cell.querySelector(".dirty-dot")
      if (dot) dot.remove()
    })
    this.element.querySelectorAll(".ring-indigo-500").forEach(cell => {
      cell.classList.remove("ring-2", "ring-inset", "ring-indigo-500", "after:content-['*']", "after:absolute", "after:top-0", "after:right-1", "after:text-[10px]", "after:font-black", "after:text-indigo-600")
      const dot = cell.querySelector(".dirty-dot")
      if (dot) dot.remove()
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

  navigate(event) {
    if (event) event.preventDefault()

    const startDate = this.navStartDateTarget.value
    const roomTypeId = this.hasNavRoomTypeTarget ? this.navRoomTypeTarget.value : null
    
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

  navigateMonth(event) {
    if (event) event.preventDefault()

    const month = this.navMonthTarget.value
    if (!month) return

    const roomTypeId = this.hasNavRoomTypeTarget ? this.navRoomTypeTarget.value : null

    const url = new URL(window.location.href)
    url.searchParams.set("month", month)
    url.searchParams.set("days", "month")
    url.searchParams.delete("start_date")
    if (roomTypeId) {
      url.searchParams.set("room_type_id", roomTypeId)
    } else {
      url.searchParams.delete("room_type_id")
    }

    const currentParams = new URLSearchParams(window.location.search)
    if (currentParams.has("tab")) url.searchParams.set("tab", currentParams.get("tab"))
    if (currentParams.has("subtab")) url.searchParams.set("subtab", currentParams.get("subtab"))

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
    const fieldName = target.dataset.fieldName || target.name.split("[").pop().replace("]", "")
    this.touchedFields.add(fieldName)
  }

  // The editor renders one input per adult count the clicked category can take,
  // so every rendered field is in scope — no visibility filtering needed.
  occupancyPricesFromForm() {
    return this.occupancyPriceFieldTargets.reduce((prices, field) => {
      if (field.value !== "") prices[field.dataset.adults] = field.value
      return prices
    }, {})
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

  showLockTip(event) {
    if (!this.hasLockTipTarget) return
    event.preventDefault()
    event.stopPropagation()

    const tip = this.lockTipTarget
    const rect = event.currentTarget.getBoundingClientRect()

    tip.classList.remove("hidden")
    tip.style.position = "fixed"
    tip.style.zIndex = "9999"

    const tipRect = tip.getBoundingClientRect()
    const viewportPadding = 8

    let left = rect.left + rect.width / 2 - tipRect.width / 2
    left = Math.max(viewportPadding, Math.min(left, window.innerWidth - tipRect.width - viewportPadding))

    let top = rect.bottom + 8
    if (top + tipRect.height > window.innerHeight - viewportPadding) {
      top = rect.top - tipRect.height - 8
    }

    tip.style.left = `${left}px`
    tip.style.top = `${top}px`

    if (!this.boundHideLockTipOutside) {
      this.boundHideLockTipOutside = (e) => {
        if (!tip.contains(e.target)) this.hideLockTip()
      }
    }
    document.removeEventListener("click", this.boundHideLockTipOutside)
    document.addEventListener("click", this.boundHideLockTipOutside)
  }

  hideLockTip() {
    if (!this.hasLockTipTarget) return
    this.lockTipTarget.classList.add("hidden")
    if (this.boundHideLockTipOutside) {
      document.removeEventListener("click", this.boundHideLockTipOutside)
    }
  }
}
