import { Controller } from "@hotwired/stimulus"

const EXPORT_LINK_IDS = ["cashier-export-pdf-link", "cashier-export-excel-link", "cashier-export-csv-link"]
const SELECTED_TRANSACTIONS_PARAM = "selected_transaction_ids[]"

export default class extends Controller {
  changed(event) {
    const input = event.target
    if (input.dataset.cashierSelectAll) return this.toggleAllTransactions(input)
    if (input.dataset.cashierTransactionSelection) return this.selectionChanged()
  }

  toggleAllTransactions(input) {
    const section = input.closest("[data-cashier-section]")
    if (!section) return

    section.querySelectorAll("input[data-cashier-transaction-selection]").forEach(row => {
      row.checked = input.checked
    })
    this.selectionChanged()
  }

  selectionChanged() {
    const selected = this.transactionSelectionInputs.filter(input => input.checked)

    this.selectAllInputs.forEach(selectAll => {
      const section = selectAll.closest("[data-cashier-section]")
      const rows = section ? Array.from(section.querySelectorAll("input[data-cashier-transaction-selection]")) : []
      const checkedRows = rows.filter(row => row.checked)
      selectAll.checked = rows.length > 0 && checkedRows.length === rows.length
      selectAll.indeterminate = checkedRows.length > 0 && checkedRows.length < rows.length
    })

    const summary = this.element.querySelector("[data-cashier-selection-summary]")
    const count = this.element.querySelector("[data-cashier-selection-count]")
    if (summary) summary.hidden = selected.length === 0
    if (count) count.textContent = selected.length.toString()

    this.syncExportLinks(selected)
  }

  syncExportLinks(selectedInputs) {
    EXPORT_LINK_IDS.forEach(linkId => {
      const link = document.getElementById(linkId)
      if (!link) return

      const exportUrl = new URL(link.href, window.location.origin)
      exportUrl.searchParams.delete(SELECTED_TRANSACTIONS_PARAM)
      selectedInputs.forEach(input => exportUrl.searchParams.append(SELECTED_TRANSACTIONS_PARAM, input.value))
      link.href = exportUrl.pathname + exportUrl.search
    })
  }

  get transactionSelectionInputs() {
    return Array.from(this.element.querySelectorAll("input[data-cashier-transaction-selection]"))
  }

  get selectAllInputs() {
    return Array.from(this.element.querySelectorAll("input[data-cashier-select-all]"))
  }
}
