import { Controller } from "@hotwired/stimulus"

const EXPORT_LINK_IDS = ["cashier-export-pdf-link", "cashier-export-excel-link", "cashier-export-csv-link"]
const SELECTION_PARAMS = [
  "selected_transaction_ids[]", "selected_cashier_groups[]", "excluded_transaction_ids[]",
  "cashier_selection_group_by"
]

export default class extends Controller {
  static values = { preferenceUrl: String }

  connect() {
    this.selectedIds = new Set()
    this.selectedGroups = new Set()
    this.excludedIds = new Set()
  }

  changed(event) {
    const input = event.target
    if (input.name === "visible_columns[]") return this.columnChanged(input)
    if (input.name?.startsWith("cashier_") && input.name.endsWith("[]")) return this.filterChanged(input)
    if (input.name === "cashier_group_by") return this.groupingChanged(input)
    if (input.dataset.cashierSelectPage) return this.togglePage(input)
    if (input.dataset.cashierGroupSelection) return this.toggleGroup(input)
    if (input.dataset.cashierTransactionSelection) return this.toggleTransaction(input)
  }

  openView(event) {
    const href = event.currentTarget.dataset.href
    if (href) window.location.assign(href)
  }

  groupingChanged(input) {
    const url = new URL(window.location.href)
    url.searchParams.set("cashier_group_by", input.value)
    url.searchParams.delete("cashier_page")
    window.location.assign(url)
  }

  filterChanged(input) {
    const url = new URL(window.location.href)
    const name = input.name.replace(/\[\]$/, "")
    const inputs = Array.from(this.element.querySelectorAll(`input[name="${CSS.escape(input.name)}"]`))

    if (input.value === "__all__") {
      url.searchParams.delete(`${name}[]`)
    } else {
      const selected = inputs.filter(item => item.value !== "__all__" && item.checked).map(item => item.value)
      url.searchParams.delete(`${name}[]`)
      selected.forEach(value => url.searchParams.append(`${name}[]`, value))
    }
    url.searchParams.delete("cashier_page")
    window.location.assign(url)
  }

  async columnChanged(input) {
    const selected = this.columnInputs.filter(column => column.checked)
    if (selected.length === 0) {
      input.checked = true
      this.announce("Keep at least one column visible.")
      return
    }

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
      window.location.reload()
    } catch (error) {
      input.checked = !input.checked
      this.announce(error.message)
    }
  }

  async resetColumns(event) {
    event.preventDefault()
    try {
      const response = await fetch(this.preferenceUrlValue, {
        method: "DELETE",
        headers: { "Accept": "application/json", "X-CSRF-Token": this.csrfToken }
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "The default columns could not be restored.")
      window.location.reload()
    } catch (error) {
      this.announce(error.message)
    }
  }

  togglePage(input) {
    this.transactionInputs.forEach(row => {
      row.checked = input.checked
      this.updateTransactionSelection(row)
    })
    this.selectionChanged()
  }

  toggleGroup(input) {
    const key = input.dataset.cashierGroupSelection
    if (input.checked) this.selectedGroups.add(key)
    else this.selectedGroups.delete(key)

    this.transactionInputs.filter(row => row.closest("tr")?.dataset.cashierGroup === key).forEach(row => {
      row.checked = input.checked
      this.selectedIds.delete(row.value)
      this.excludedIds.delete(row.value)
    })
    this.selectionChanged()
  }

  toggleTransaction(input) {
    this.updateTransactionSelection(input)
    this.selectionChanged()
  }

  updateTransactionSelection(input) {
    const group = input.closest("tr")?.dataset.cashierGroup
    if (this.selectedGroups.has(group)) {
      this.selectedIds.delete(input.value)
      if (input.checked) this.excludedIds.delete(input.value)
      else this.excludedIds.add(input.value)
    } else if (input.checked) {
      this.selectedIds.add(input.value)
    } else {
      this.selectedIds.delete(input.value)
    }
  }

  selectionChanged() {
    this.groupInputs.forEach(input => {
      const key = input.dataset.cashierGroupSelection
      const rows = this.transactionInputs.filter(row => row.closest("tr")?.dataset.cashierGroup === key)
      const checked = rows.filter(row => row.checked)
      input.checked = this.selectedGroups.has(key) && this.excludedForGroup(key).length === 0
      input.indeterminate = checked.length > 0 && (!input.checked || checked.length < rows.length)
    })

    const checkedRows = this.transactionInputs.filter(input => input.checked)
    if (this.pageInput) {
      this.pageInput.checked = checkedRows.length > 0 && checkedRows.length === this.transactionInputs.length
      this.pageInput.indeterminate = checkedRows.length > 0 && checkedRows.length < this.transactionInputs.length
    }

    const selectedCount = this.selectionCount
    const summary = this.element.querySelector("[data-cashier-selection-summary]")
    const filteredSummary = this.element.querySelector("[data-cashier-filtered-summary]")
    const count = this.element.querySelector("[data-cashier-selection-count]")
    if (summary) summary.hidden = selectedCount === 0
    if (filteredSummary) filteredSummary.hidden = selectedCount > 0
    if (count) count.textContent = selectedCount.toString()
    this.element.querySelectorAll("[data-cashier-export-label]").forEach(label => {
      if (!label.dataset.defaultLabel) label.dataset.defaultLabel = label.textContent.trim()
      label.textContent = selectedCount > 0 ? `Export ${selectedCount} selected` : label.dataset.defaultLabel
    })
    this.syncExportLinks()
  }

  syncExportLinks() {
    EXPORT_LINK_IDS.forEach(linkId => {
      const link = document.getElementById(linkId)
      if (!link) return
      const url = new URL(link.href, window.location.origin)
      SELECTION_PARAMS.forEach(name => url.searchParams.delete(name))
      this.selectedIds.forEach(id => url.searchParams.append("selected_transaction_ids[]", id))
      this.selectedGroups.forEach(key => url.searchParams.append("selected_cashier_groups[]", key))
      this.excludedIds.forEach(id => url.searchParams.append("excluded_transaction_ids[]", id))
      if (this.selectedGroups.size > 0) {
        url.searchParams.set("cashier_selection_group_by", this.groupingInput?.value || "handling")
      }
      link.href = url.pathname + url.search
    })
  }

  excludedForGroup(key) {
    return this.transactionInputs.filter(row => {
      return row.closest("tr")?.dataset.cashierGroup === key && this.excludedIds.has(row.value)
    })
  }

  get selectionCount() {
    const groupCount = this.groupInputs.reduce((total, input) => {
      if (!this.selectedGroups.has(input.dataset.cashierGroupSelection)) return total
      const count = Number(input.closest("tr")?.dataset.cashierGroupCount || 0)
      return total + count - this.excludedForGroup(input.dataset.cashierGroupSelection).length
    }, 0)
    return groupCount + this.selectedIds.size
  }

  announce(message) {
    const status = this.element.querySelector("[data-cashier-preference-status]")
    if (status) status.textContent = message
  }

  get transactionInputs() {
    return Array.from(this.element.querySelectorAll("input[data-cashier-transaction-selection]"))
  }

  get groupInputs() {
    return Array.from(this.element.querySelectorAll("input[data-cashier-group-selection]"))
  }

  get pageInput() {
    return this.element.querySelector("input[data-cashier-select-page]")
  }

  get groupingInput() {
    return this.element.querySelector('input[name="cashier_group_by"]')
  }

  get columnInputs() {
    return Array.from(this.element.querySelectorAll('input[name="visible_columns[]"]'))
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
