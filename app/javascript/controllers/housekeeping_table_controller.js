import { Controller } from "@hotwired/stimulus"

const RESULTS_FRAME_ID = "housekeeping_tasks_results"
const EXPORT_LINK_IDS = ["export-pdf-link", "export-excel-link", "export-csv-link"]
const FILTER_NAMES = [
  "room_type_ids[]",
  "room_statuses[]",
  "assigned_to_ids[]",
  "booking_statuses[]"
]
const BOARD_PARAM_NAMES = [...FILTER_NAMES, "sort", "direction"]
const COLUMN_FILTER_NAMES = {
  room_type: "room_type_ids[]",
  room_status: "room_statuses[]",
  assigned_to: "assigned_to_ids[]",
  booking_status: "booking_statuses[]"
}

export default class extends Controller {
  static values = { preferenceUrl: String }

  disconnect() {
    this.cancelScheduledReopen()
  }

  changed(event) {
    const input = event.target
    if (input.name === "visible_columns[]") return this.columnChanged(input)
    if (input.dataset.housekeepingSelectAll) return this.toggleAllRooms(input)
    if (input.dataset.housekeepingRoomSelection) return this.roomSelectionChanged()
    if (FILTER_NAMES.includes(input.name)) return this.filterChanged(input)
  }

  filterChanged(input) {
    const inputs = Array.from(this.element.querySelectorAll(`input[name="${input.name}"]`))
    const allInput = inputs.find(candidate => candidate.value === "__all__")
    const optionInputs = inputs.filter(candidate => candidate !== allInput)

    if (input === allInput) {
      optionInputs.forEach(option => this.setChecked(option, input.checked))
    } else if (!input.checked) {
      if (allInput) this.setChecked(allInput, false)
    } else if (optionInputs.every(option => option.checked)) {
      if (allInput) this.setChecked(allInput, true)
    }

    const url = new URL(window.location.href)
    url.searchParams.delete(input.name)

    const selectedOptions = optionInputs.filter(option => option.checked)
    if (selectedOptions.length === optionInputs.length) {
      if (allInput) this.setChecked(allInput, true)
    } else if (selectedOptions.length === 0) {
      url.searchParams.append(input.name, "__none__")
    } else {
      selectedOptions.forEach(option => url.searchParams.append(input.name, option.value))
    }

    this.clearRoomSelection()
    this.scheduleReopen(input.closest(".dropdown-menu-root"))
    this.navigateTo(url)
  }

  async columnChanged(input) {
    const selected = this.selectedColumnInputs()
    if (selected.length === 0) {
      this.setChecked(input, true)
      this.updateColumnAvailability()
      this.announcePreference("Keep at least one column visible.")
      return
    }

    const previousChecked = !input.checked
    this.setPreferenceBusy(true)

    try {
      const response = await fetch(this.preferenceUrlValue, {
        method: "PATCH",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ visible_columns: selected.map(column => column.value) })
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "The column preference could not be saved.")

      this.clearRoomSelection()
      const url = this.urlWithoutHiddenColumnState(input.value, input.checked)
      window.history.replaceState(window.history.state, "", url)
      this.reloadFrame(url)
      this.announcePreference("Visible columns saved.")
    } catch (error) {
      this.setChecked(input, previousChecked)
      this.announcePreference(error.message)
    } finally {
      this.setPreferenceBusy(false)
    }
  }

  async resetColumns(event) {
    event.preventDefault()
    this.setPreferenceBusy(true)

    try {
      const response = await fetch(this.preferenceUrlValue, {
        method: "DELETE",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken }
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "The default columns could not be restored.")

      this.columnInputs.forEach(input => this.setChecked(input, true))
      this.clearRoomSelection()
      this.reloadFrame(new URL(window.location.href))
      this.announcePreference("Default columns restored.")
    } catch (error) {
      this.announcePreference(error.message)
    } finally {
      this.setPreferenceBusy(false)
    }
  }

  toggleAllRooms(input) {
    this.roomSelectionInputs.forEach(roomInput => {
      roomInput.checked = input.checked
    })
    this.roomSelectionChanged()
  }

  roomSelectionChanged() {
    const inputs = this.roomSelectionInputs
    const selected = inputs.filter(input => input.checked)
    const selectAll = this.selectAllInput

    if (selectAll) {
      selectAll.checked = inputs.length > 0 && selected.length === inputs.length
      selectAll.indeterminate = selected.length > 0 && selected.length < inputs.length
    }

    const summary = this.element.querySelector("[data-housekeeping-selection-summary]")
    const count = this.element.querySelector("[data-housekeeping-selection-count]")
    const resultCount = this.element.querySelector("[data-housekeeping-result-count]")
    if (summary) summary.hidden = selected.length === 0
    if (count) count.textContent = selected.length.toString()
    if (resultCount) resultCount.hidden = selected.length > 0

    this.element.querySelectorAll("[data-housekeeping-export-label]").forEach(label => {
      label.textContent = selected.length > 0 ? `Export ${selected.length}` : "Export"
    })
    this.syncSelectedRooms(selected)
  }

  clearRoomSelection() {
    this.roomSelectionInputs.forEach(input => { input.checked = false })
    if (this.selectAllInput) {
      this.selectAllInput.checked = false
      this.selectAllInput.indeterminate = false
    }
    this.roomSelectionChanged()
  }

  navigate(event) {
    event.preventDefault()
    this.clearRoomSelection()
    this.navigateTo(new URL(event.currentTarget.href, window.location.origin))
  }

  navigateTo(url) {
    window.history.replaceState(window.history.state, "", url)
    this.syncExportLinks(url)
    this.reloadFrame(url)
  }

  reloadFrame(url) {
    const frame = document.getElementById(RESULTS_FRAME_ID)
    if (frame) frame.src = url.toString()
  }

  frameLoaded(event) {
    if (event.target?.id !== RESULTS_FRAME_ID) return

    this.clearRoomSelection()
    const summary = event.target.querySelector("[data-board-summary]")
    const resultCount = this.element.querySelector("[data-housekeeping-result-count]")
    if (summary && resultCount) resultCount.textContent = summary.textContent.trim().replace(/\.$/, "")
  }

  syncExportLinks(sourceUrl) {
    EXPORT_LINK_IDS.forEach(linkId => {
      const link = document.getElementById(linkId)
      if (!link) return

      const exportUrl = new URL(link.href, window.location.origin)
      BOARD_PARAM_NAMES.forEach(name => {
        exportUrl.searchParams.delete(name)
        sourceUrl.searchParams.getAll(name).forEach(value => exportUrl.searchParams.append(name, value))
      })
      this.removeSelectedRoomParams(exportUrl)
      link.href = exportUrl.pathname + exportUrl.search
    })
  }

  syncSelectedRooms(selectedInputs) {
    EXPORT_LINK_IDS.forEach(linkId => {
      const link = document.getElementById(linkId)
      if (!link) return

      const exportUrl = new URL(link.href, window.location.origin)
      this.removeSelectedRoomParams(exportUrl)
      selectedInputs.forEach(input => exportUrl.searchParams.append(input.name, input.value))
      link.href = exportUrl.pathname + exportUrl.search
    })
  }

  removeSelectedRoomParams(url) {
    Array.from(url.searchParams.keys())
      .filter(key => key.startsWith("selected_rooms["))
      .forEach(key => url.searchParams.delete(key))
  }

  urlWithoutHiddenColumnState(columnKey, checked) {
    const url = new URL(window.location.href)
    if (checked) return url

    const filterName = COLUMN_FILTER_NAMES[columnKey]
    if (filterName) url.searchParams.delete(filterName)
    if (["arrival", "departure"].includes(columnKey) && url.searchParams.get("sort") === columnKey) {
      url.searchParams.delete("sort")
      url.searchParams.delete("direction")
    }
    return url
  }

  setPreferenceBusy(busy) {
    this.columnInputs.forEach(input => {
      input.disabled = busy
      input.closest("[role='menuitemcheckbox']")?.setAttribute("aria-disabled", busy.toString())
    })
    if (!busy) this.updateColumnAvailability()
    EXPORT_LINK_IDS.forEach(linkId => {
      document.getElementById(linkId)?.setAttribute("aria-disabled", busy.toString())
    })
  }

  updateColumnAvailability() {
    const selected = this.selectedColumnInputs()
    this.columnInputs.forEach(input => {
      const disabled = selected.length === 1 && input.checked
      input.disabled = disabled
      input.closest("[role='menuitemcheckbox']")?.setAttribute("aria-disabled", disabled.toString())
    })
  }

  announcePreference(message) {
    const status = this.element.querySelector("[data-housekeeping-preference-status]")
    if (status) status.textContent = message
  }

  setChecked(input, checked) {
    input.checked = checked
    input.closest("[role='menuitemcheckbox']")?.setAttribute("aria-checked", checked.toString())
  }

  scheduleReopen(dropdownRoot) {
    const trigger = dropdownRoot?.querySelector("[data-panels-ui--dropdown-menu-target~='trigger']")
    const frame = document.getElementById(RESULTS_FRAME_ID)
    if (!trigger || !frame) return

    this.cancelScheduledReopen()
    this.reopenFrame = frame
    this.reopenListener = () => trigger.click()
    frame.addEventListener("turbo:frame-load", this.reopenListener, { once: true })
  }

  cancelScheduledReopen() {
    if (!this.reopenListener) return

    this.reopenFrame?.removeEventListener("turbo:frame-load", this.reopenListener)
    this.reopenListener = null
    this.reopenFrame = null
  }

  get columnInputs() {
    return Array.from(this.element.querySelectorAll('input[name="visible_columns[]"]'))
  }

  selectedColumnInputs() {
    return this.columnInputs.filter(input => input.checked)
  }

  get roomSelectionInputs() {
    return Array.from(this.element.querySelectorAll("input[data-housekeeping-room-selection]"))
  }

  get selectAllInput() {
    return this.element.querySelector("input[data-housekeeping-select-all]")
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
