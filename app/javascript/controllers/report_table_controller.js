import { Controller } from "@hotwired/stimulus"

// Drives a grouped report table: the column picker, the header filters, the
// grouping toggle, and the row selection. Every report name is a value, so one
// controller serves every report table.
export default class extends Controller {
  static values = {
    preferenceUrl: String,
    idParam: String,
    groupParam: String,
    excludedParam: String,
    selectionGroupParam: String,
    groupingParam: String,
    pageParam: { type: String, default: "page" },
    defaultGrouping: String,
    filterParams: Array,
    dropParams: Array,
    exportLinkIds: Array,
    syncPagination: Boolean,
    columnFilters: Object,
    columnGroupings: Object,
    selectedIds: Array,
    selectedGroups: Array,
    excludedIds: Array,
    selectedIdGroups: Object,
    excludedIdGroups: Object,
    groupCounts: Object
  }

  connect() {
    this.selectedIds = new Set(this.selectedIdsValue.map(String))
    this.selectedGroups = new Set(this.selectedGroupsValue.map(String))
    this.excludedIds = new Set(this.excludedIdsValue.map(String))
    this.selectedIdGroups = { ...this.selectedIdGroupsValue }
    this.excludedIdGroups = { ...this.excludedIdGroupsValue }
    this.syncSelectionControls()
    this.syncStateLinks()
  }

  changed(event) {
    const input = event.target
    if (input.name === "visible_columns[]") return this.columnChanged(input)
    if (input.name === this.groupingParamValue) return this.groupingChanged(input)
    if (this.filterNames.includes(input.name)) return this.filterChanged(input)
    if (input.dataset.selectPage !== undefined) return this.togglePage(input)
    if (input.dataset.groupSelection !== undefined) return this.toggleGroup(input)
    if (input.dataset.recordSelection !== undefined) return this.toggleRecord(input)
  }

  openView(event) {
    const href = event.currentTarget.dataset.href
    if (href) window.location.assign(href)
  }

  // ---- navigation ----------------------------------------------------------

  groupingChanged(input) {
    const url = this.currentUrl()
    url.searchParams.set(this.groupingParamValue, input.value)
    this.resetPage(url)
    window.location.assign(url)
  }

  filterChanged(input) {
    const url = this.currentUrl()
    const inputs = Array.from(this.element.querySelectorAll(`input[name="${CSS.escape(input.name)}"]`))
    const allInput = inputs.find(item => item.value === "__all__")
    const choices = inputs.filter(item => item !== allInput)

    if (input === allInput) {
      choices.forEach(choice => { choice.checked = input.checked })
    } else if (!input.checked && allInput) {
      allInput.checked = false
    }

    const selected = choices.filter(choice => choice.checked)
    url.searchParams.delete(input.name)
    if (selected.length === choices.length) {
      if (allInput) allInput.checked = true
    } else if (selected.length === 0) {
      url.searchParams.append(input.name, "__none__")
    } else {
      selected.forEach(choice => url.searchParams.append(input.name, choice.value))
    }

    this.dropParamsValue.forEach(name => url.searchParams.delete(name))
    this.resetPage(url)
    window.location.assign(url)
  }

  // ---- columns -------------------------------------------------------------

  async columnChanged(input) {
    const selected = this.columnInputs.filter(column => column.checked)
    if (selected.length === 0) {
      input.checked = true
      this.announce("Keep at least one column visible.")
      return
    }

    try {
      await this.savePreference("PATCH", {
        visible_columns: selected.map(column => column.value)
      }, "The column preference could not be saved.")
      const url = this.currentUrl()
      if (!input.checked) this.removeHiddenColumnState(url, input.value)
      window.location.assign(url)
    } catch (error) {
      input.checked = !input.checked
      this.announce(error.message)
    }
  }

  async resetColumns(event) {
    event.preventDefault()
    try {
      await this.savePreference("DELETE", null, "The default columns could not be restored.")
      window.location.assign(this.currentUrl())
    } catch (error) {
      this.announce(error.message)
    }
  }

  async savePreference(method, body, fallbackMessage) {
    const headers = { "Accept": "application/json", "X-CSRF-Token": this.csrfToken }
    if (body) headers["Content-Type"] = "application/json"
    const response = await fetch(this.preferenceUrlValue, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.error || fallbackMessage)
    return payload
  }

  // A hidden column cannot carry a filter or a grouping, so drop both.
  removeHiddenColumnState(url, column) {
    const filterName = this.columnFiltersValue[column]
    let changed = false
    if (filterName && url.searchParams.has(filterName)) {
      url.searchParams.delete(filterName)
      changed = true
    }
    if (this.columnGroupingsValue[column] === url.searchParams.get(this.groupingParamValue)) {
      url.searchParams.set(this.groupingParamValue, this.defaultGroupingValue)
      changed = true
    }
    if (changed) this.resetPage(url)
  }

  // ---- selection -----------------------------------------------------------

  togglePage(input) {
    this.recordInputs.forEach(recordInput => {
      recordInput.checked = input.checked
      this.updateRecordSelection(recordInput)
    })
    this.selectionChanged()
  }

  toggleGroup(input) {
    const key = input.dataset.groupSelection
    if (input.checked) {
      this.selectedGroups.add(key)
      this.removeMappedValues(this.selectedIds, this.selectedIdGroups, key)
    } else {
      this.selectedGroups.delete(key)
    }
    this.removeMappedValues(this.excludedIds, this.excludedIdGroups, key)

    this.recordInputs
      .filter(item => item.closest("tr")?.dataset.recordGroup === key)
      .forEach(item => { item.checked = input.checked })
    this.selectionChanged()
  }

  toggleRecord(input) {
    this.updateRecordSelection(input)
    this.selectionChanged()
  }

  updateRecordSelection(input) {
    const id = String(input.value)
    const group = input.closest("tr")?.dataset.recordGroup
    if (this.selectedGroups.has(group)) {
      this.selectedIds.delete(id)
      delete this.selectedIdGroups[id]
      if (input.checked) {
        this.excludedIds.delete(id)
        delete this.excludedIdGroups[id]
      } else {
        this.excludedIds.add(id)
        this.excludedIdGroups[id] = group
      }
    } else if (input.checked) {
      this.selectedIds.add(id)
      this.selectedIdGroups[id] = group
    } else {
      this.selectedIds.delete(id)
      delete this.selectedIdGroups[id]
    }
  }

  removeMappedValues(set, mapping, group) {
    Object.entries(mapping).forEach(([id, mappedGroup]) => {
      if (mappedGroup !== group) return
      set.delete(id)
      delete mapping[id]
    })
  }

  selectionChanged() {
    this.syncSelectionControls()
    this.syncStateLinks()
  }

  syncSelectionControls() {
    this.recordInputs.forEach(input => {
      const group = input.closest("tr")?.dataset.recordGroup
      input.checked = this.selectedGroups.has(group)
        ? !this.excludedIds.has(String(input.value))
        : this.selectedIds.has(String(input.value))
    })

    this.groupInputs.forEach(input => {
      const key = input.dataset.groupSelection
      const total = this.groupTotal(key, input)
      const selected = this.selectedCountForGroup(key, total)
      input.checked = total > 0 && selected === total
      input.indeterminate = selected > 0 && selected < total
    })

    const selectedOnPage = this.recordInputs.filter(input => input.checked).length
    if (this.pageInput) {
      this.pageInput.checked = this.recordInputs.length > 0 && selectedOnPage === this.recordInputs.length
      this.pageInput.indeterminate = selectedOnPage > 0 && selectedOnPage < this.recordInputs.length
    }

    const count = this.selectedCount
    this.toggleText("[data-report-table-selection-summary]", count > 0)
    this.toggleText("[data-report-table-filtered-summary]", count === 0)
    const countElement = this.element.querySelector("[data-report-table-selection-count]")
    if (countElement) countElement.textContent = count.toString()
    this.element.querySelectorAll("[data-report-table-export-label]").forEach(label => {
      if (!label.dataset.defaultLabel) label.dataset.defaultLabel = label.textContent.trim()
      label.textContent = count > 0 ? `Export ${count} selected` : label.dataset.defaultLabel
    })
  }

  toggleText(selector, visible) {
    const element = this.element.querySelector(selector)
    if (element) element.hidden = !visible
  }

  groupTotal(key, input) {
    return Number(this.groupCountsValue[key] ?? input.closest("tr")?.dataset.groupCount ?? 0)
  }

  selectedCountForGroup(key, total) {
    if (this.selectedGroups.has(key)) {
      return total - Object.values(this.excludedIdGroups).filter(group => group === key).length
    }
    return Object.values(this.selectedIdGroups).filter(group => group === key).length
  }

  get selectedCount() {
    const grouped = Array.from(this.selectedGroups).reduce((total, key) => {
      return total + this.selectedCountForGroup(key, Number(this.groupCountsValue[key] || 0))
    }, 0)
    return grouped + this.selectedIds.size
  }

  // Writes the selection into every link that leaves this page with it.
  syncStateLinks() {
    const links = this.exportLinkIdsValue.map(id => document.getElementById(id)).filter(Boolean)
    if (this.syncPaginationValue) {
      links.push(...this.element.querySelectorAll("[data-slot='pagination-link'][href]"))
    }
    links.forEach(link => {
      const url = new URL(link.href, window.location.origin)
      this.clearSelectionParams(url)
      this.selectedIds.forEach(id => url.searchParams.append(`${this.idParamValue}[]`, id))
      this.selectedGroups.forEach(key => url.searchParams.append(`${this.groupParamValue}[]`, key))
      this.excludedIds.forEach(id => url.searchParams.append(`${this.excludedParamValue}[]`, id))
      if (this.selectedIds.size > 0 || this.selectedGroups.size > 0) {
        url.searchParams.set(this.selectionGroupParamValue, this.groupingInput?.value || this.defaultGroupingValue)
      }
      link.href = url.pathname + url.search
    })
  }

  clearSelectionParams(url) {
    const names = [
      `${this.idParamValue}[]`, `${this.groupParamValue}[]`, `${this.excludedParamValue}[]`,
      this.selectionGroupParamValue
    ]
    names.forEach(name => url.searchParams.delete(name))
  }

  // ---- helpers -------------------------------------------------------------

  // The page can live inside a Turbo frame. Turbo advances the address bar
  // only when the frame asks for it, so read the URL that the server rendered.
  currentUrl() {
    const rendered = this.element.dataset.reportTableUrl
    return new URL(rendered || window.location.href, window.location.origin)
  }

  resetPage(url) {
    url.searchParams.delete(this.pageParamValue)
    this.clearSelectionParams(url)
  }

  announce(message) {
    const status = this.element.querySelector("[data-report-table-status]")
    if (status) status.textContent = message
  }

  get filterNames() {
    return this.filterParamsValue.map(name => `${name}[]`)
  }

  get recordInputs() {
    return Array.from(this.element.querySelectorAll("input[data-record-selection]"))
  }

  get groupInputs() {
    return Array.from(this.element.querySelectorAll("input[data-group-selection]"))
  }

  get pageInput() {
    return this.element.querySelector("input[data-select-page]")
  }

  get groupingInput() {
    return this.element.querySelector(`input[name="${CSS.escape(this.groupingParamValue)}"]`)
  }

  get columnInputs() {
    return Array.from(this.element.querySelectorAll('input[name="visible_columns[]"]'))
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
