import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "amenitiesPanel", "numberingPanel", "roomName", "numberingRoomName",
    "amenityPicker", "rangeFields", "customFields", "rangeStart",
    "customNumbers", "numberingMode", "numberBadges", "numberBadgeTemplate",
    "numberingStatus", "numberingError", "amenityInputs", "amenitySummary",
    "numberInputs", "numberMode", "numberSummary"
  ]

  connect() {
    this.sheet = this.element.querySelector("#onboarding_action_sheet")
    this.activeRow = null
    this.activeTrigger = null
    this.editor = null
  }

  openAmenities(event) {
    this.activateRow(event)
    this.editor = "amenities"
    this.amenitiesPanelTarget.hidden = false
    this.numberingPanelTarget.hidden = true
    this.roomNameTarget.textContent = this.roomName()

    const selected = new Set(Array.from(this.activeRow.querySelectorAll("[data-room-amenity-value]"), input => input.value))
    const picker = this.amenitySelect()
    Array.from(picker.options).forEach(option => { option.selected = selected.has(option.value) })
    picker.dispatchEvent(new Event("change", { bubbles: true }))
    this.openSheet()
  }

  openNumbering(event) {
    this.activateRow(event)
    this.editor = "numbering"
    this.amenitiesPanelTarget.hidden = true
    this.numberingPanelTarget.hidden = false
    this.numberingRoomNameTarget.textContent = this.roomName()

    const numbers = this.rowNumberInputs().map(input => input.value)
    const storedMode = this.rowNumberMode().value
    const mode = numbers.length === 0 ? "quantity" : (storedMode === "custom" ? "custom" : "range")
    this.numberingModeTargets.forEach(option => { option.checked = option.value === mode })

    if (mode === "range") this.rangeStartTarget.value = this.firstNumericValue(numbers) || 101
    this.customNumbersTarget.value = numbers.join(", ")
    this.renderNumberingPreview()
    this.openSheet()
  }

  applySheet() {
    if (!this.activeRow) return

    if (this.editor === "amenities") {
      this.applyAmenities()
    } else if (!this.applyNumbering()) {
      return
    }

    this.closeSheet()
  }

  cancelSheet() {
    this.closeSheet()
  }

  numberingChanged() {
    this.renderNumberingPreview()
  }

  quantityChanged(event) {
    const row = event.currentTarget.closest("[data-record-table-target='row']")
    if (!row) return

    const count = row.querySelectorAll("[data-room-number-value]").length
    if (count === 0) return

    const quantity = this.quantityFor(row)
    const summary = row.querySelector("[data-onboarding-room-grid-target='numberSummary']")
    summary.hidden = count === quantity
    summary.textContent = count === quantity ? "" : `${count} of ${quantity} numbers · needs attention`
  }

  activateRow(event) {
    this.activeRow = event.currentTarget.closest("[data-record-table-target='row']")
    this.activeTrigger = event.currentTarget
  }

  roomName() {
    return this.activeRow.querySelector("input[name$='[name]']")?.value.trim() || "this room category"
  }

  openSheet() {
    if (!this.sheet.open) this.sheet.showModal()
  }

  closeSheet() {
    const trigger = this.activeTrigger
    const controller = window.Stimulus?.getControllerForElementAndIdentifier(this.sheet, "panels-ui--sheet")
    if (controller) controller.close()
    else if (this.sheet.open) this.sheet.close()

    window.setTimeout(() => trigger?.focus(), 350)
    this.activeRow = null
    this.activeTrigger = null
  }

  applyAmenities() {
    const values = Array.from(this.amenitySelect().selectedOptions, option => option.value)
    const container = this.activeRow.querySelector("[data-onboarding-room-grid-target='amenityInputs']")
    container.replaceChildren(...values.map(value => this.hiddenInput(`${this.fieldPrefix()}[amenities][]`, value, "roomAmenityValue")))

    const summary = this.activeRow.querySelector("[data-onboarding-room-grid-target='amenitySummary']")
    summary.textContent = values.length === 0 ? "Add amenities" : `${values.length} amenities`
  }

  applyNumbering() {
    const result = this.numberingResult()
    this.showNumberingError(result.errors)
    if (result.errors.length > 0) return false

    this.rowNumberMode().value = result.persistedMode
    const container = this.activeRow.querySelector("[data-onboarding-room-grid-target='numberInputs']")
    container.replaceChildren(...result.numbers.map(number => this.hiddenInput(`${this.fieldPrefix()}[room_numbers][]`, number, "roomNumberValue")))

    this.renderRowNumbering(result.numbers)
    const summary = this.activeRow.querySelector("[data-onboarding-room-grid-target='numberSummary']")
    summary.hidden = true
    summary.textContent = ""
    return true
  }

  renderNumberingPreview() {
    const result = this.numberingResult()
    const mode = this.selectedNumberingMode()
    this.rangeFieldsTarget.hidden = mode !== "range"
    this.customFieldsTarget.hidden = mode !== "custom"

    const badges = result.numbers.map(number => this.numberBadge(number))
    this.numberBadgesTarget.replaceChildren(...badges)

    const quantity = this.quantityFor(this.activeRow)
    this.numberingStatusTarget.textContent = result.numbers.length === 0
      ? "Quantity-only inventory"
      : `${result.numbers.length} of ${quantity} room numbers configured`
    this.showNumberingError(result.errors)
  }

  numberingResult() {
    const mode = this.selectedNumberingMode()
    const quantity = this.quantityFor(this.activeRow)
    if (mode === "quantity") return { numbers: [], errors: [], persistedMode: "range" }

    if (quantity < 1) {
      return { numbers: [], errors: [ "Enter Total rooms before configuring room numbers." ], persistedMode: mode }
    }

    let numbers
    const errors = []
    if (mode === "range") {
      const start = Number.parseInt(this.rangeStartTarget.value, 10)
      if (!Number.isInteger(start) || start < 1) {
        errors.push("Enter a valid starting number.")
        numbers = []
      } else {
        numbers = Array.from({ length: quantity }, (_value, index) => `${start + index}`)
      }
    } else {
      const raw = this.customNumbersTarget.value
      const pieces = raw.split(/[,\n]/).map(value => value.trim())
      if (pieces.some(value => value === "")) errors.push("Room numbers cannot be blank.")
      numbers = pieces.filter(Boolean)
      if (new Set(numbers).size !== numbers.length) errors.push("Room numbers must be unique.")
      if (numbers.length !== quantity) errors.push(`Enter exactly ${quantity} room numbers.`)
    }

    return { numbers, errors, persistedMode: mode === "custom" ? "custom" : "range" }
  }

  showNumberingError(errors) {
    this.numberingErrorTarget.hidden = errors.length === 0
    this.numberingErrorTarget.textContent = errors.join(" ")
  }

  selectedNumberingMode() {
    return this.numberingModeTargets.find(option => option.checked)?.value || "quantity"
  }

  quantityFor(row) {
    return Number.parseInt(row?.querySelector("[data-onboarding-room-grid-field='quantity']")?.value, 10) || 0
  }

  rowNumberInputs() {
    return Array.from(this.activeRow.querySelectorAll("[data-room-number-value]"))
  }

  rowNumberMode() {
    return this.activeRow.querySelector("[data-onboarding-room-grid-target='numberMode']")
  }

  amenitySelect() {
    return this.amenityPickerTarget.querySelector("select")
  }

  renderRowNumbering(numbers) {
    const container = this.activeRow.querySelector("[data-room-number-badges]")
    if (numbers.length > 0) {
      container.replaceChildren(...numbers.map(number => this.numberBadge(number)))
      return
    }

    const quantityOnly = document.createElement("span")
    quantityOnly.className = "text-xs text-muted-foreground"
    quantityOnly.textContent = "Quantity only"
    container.replaceChildren(quantityOnly)
  }

  numberBadge(number) {
    const fragment = this.numberBadgeTemplateTarget.content.cloneNode(true)
    fragment.querySelector("[data-size='xs']").textContent = number
    return fragment
  }

  fieldPrefix() {
    return `room_entries[${this.activeRow.dataset.recordTableKey}]`
  }

  hiddenInput(name, value, datasetKey) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    input.dataset[datasetKey] = value
    return input
  }

  firstNumericValue(numbers) {
    const value = Number.parseInt(numbers[0], 10)
    return Number.isInteger(value) ? value : null
  }
}
