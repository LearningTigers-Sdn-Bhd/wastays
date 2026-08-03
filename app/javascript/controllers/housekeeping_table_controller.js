import { Controller } from "@hotwired/stimulus"

const RESULTS_FRAME_ID = "housekeeping_tasks_results"
const EXPORT_LINK_IDS = ["export-pdf-link", "export-excel-link", "export-csv-link"]
const BOARD_PARAM_NAMES = [
  "room_type_ids[]",
  "room_statuses[]",
  "assigned_to_ids[]",
  "booking_statuses[]",
  "sort",
  "direction"
]

export default class extends Controller {
  disconnect() {
    this.cancelScheduledReopen()
  }

  filterChanged(event) {
    const input = event.target
    const filterNames = [
      "room_type_ids[]",
      "room_statuses[]",
      "assigned_to_ids[]",
      "booking_statuses[]"
    ]
    if (!filterNames.includes(input.name)) return

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

    // The filter <th> cells are data-turbo-permanent, so their checkbox state
    // and Stimulus controllers survive the frame swap. But Turbo still detaches
    // and reinserts that DOM subtree, and the native Popover API force-closes
    // any open popover the instant it's detached — even though it's the same
    // node. Reopening the trigger once the frame settles undoes that auto-close.
    this.scheduleReopen(input.closest(".dropdown-menu-root"))

    this.navigateTo(url)
  }

  setChecked(input, checked) {
    input.checked = checked
    input.closest('[role="menuitemcheckbox"]')?.setAttribute("aria-checked", checked.toString())
  }

  navigate(event) {
    event.preventDefault()
    this.navigateTo(new URL(event.currentTarget.href, window.location.origin))
  }

  navigateTo(url) {
    const frame = document.getElementById(RESULTS_FRAME_ID)
    if (!frame) return

    window.history.replaceState(window.history.state, "", url)
    this.syncExportLinks(url)
    frame.src = url.toString()
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
      link.href = exportUrl.pathname + exportUrl.search
    })
  }

  scheduleReopen(dropdownRoot) {
    const trigger = dropdownRoot?.querySelector('[data-panels-ui--dropdown-menu-target~="trigger"]')
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
}
