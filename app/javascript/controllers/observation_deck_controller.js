import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame", "desktopInspector", "mobileInspector", "inspectorDialog", "settingsDialog", "announcer", "search", "filterForm", "loading", "stream", "themeOption"]

  connect() {
    this.mediaQuery = window.matchMedia("(max-width: 1279px)")
    this.colorSchemeQuery = window.matchMedia("(prefers-color-scheme: dark)")
    this.resize = this.resize.bind(this)
    this.updateSystemTheme = this.updateSystemTheme.bind(this)
    this.mediaQuery.addEventListener("change", this.resize)
    this.colorSchemeQuery.addEventListener("change", this.updateSystemTheme)
    this.restoreTheme()
    this.resize()
  }

  disconnect() {
    this.mediaQuery?.removeEventListener("change", this.resize)
    this.colorSchemeQuery?.removeEventListener("change", this.updateSystemTheme)
    window.clearTimeout(this.searchTimeout)
  }

  search() {
    window.clearTimeout(this.searchTimeout)
    this.searchTimeout = window.setTimeout(() => this.filterFormTarget.requestSubmit(), 250)
  }

  startRefresh(event) {
    event.currentTarget.classList.add("is-spinning")
    event.currentTarget.setAttribute("aria-busy", "true")
  }

  openInspector(event) {
    this.lastTrigger = event.currentTarget
    this.selectRow(event.currentTarget)
    this.pendingInspectorOpen = this.mediaQuery.matches
  }

  openRow(event) {
    if (event.target.closest("a, button, input, select, textarea")) return

    event.currentTarget.querySelector("a[data-turbo-frame='entry_detail_frame']")?.click()
  }

  closeInspector(event) {
    if (event?.type === "cancel") event.preventDefault()
    if (this.hasInspectorDialogTarget && this.inspectorDialogTarget.open) this.inspectorDialogTarget.close()
  }

  openSettings(event) {
    this.lastTrigger = event.currentTarget
    this.settingsDialogTarget.showModal()
  }

  closeSettings(event) {
    if (event?.type === "cancel") event.preventDefault()
    if (this.settingsDialogTarget.open) this.settingsDialogTarget.close()
  }

  setTheme(event) {
    this.applyTheme(event.currentTarget.value)
  }

  restoreFocus() {
    this.lastTrigger?.focus()
  }

  startLoading(event) {
    if (!this.element.contains(event.target) || event.target.id !== "entries_frame") return

    this.loadingTargets.forEach((target) => { target.hidden = false })
    this.streamTarget.setAttribute("aria-busy", "true")
  }

  stopLoading(event) {
    if (event.target.id !== "entries_frame" && event.target.id !== "entry_detail_frame") return

    this.loadingTargets.forEach((target) => { target.hidden = true })
    if (event.target.id === "entries_frame") {
      this.announcerTarget.textContent = "Event stream updated."
      this.streamTarget.setAttribute("aria-busy", "false")
    }

    if (event.target.id === "entry_detail_frame" && this.pendingInspectorOpen && this.mediaQuery.matches) {
      this.pendingInspectorOpen = false
      this.inspectorDialogTarget.showModal()
      this.inspectorDialogTarget.querySelector(".observation-deck__sheet-close")?.focus()
    }
  }

  resize() {
    if (!this.hasFrameTarget) return

    const destination = this.mediaQuery.matches ? this.mobileInspectorTarget : this.desktopInspectorTarget
    if (this.frameTarget.parentElement !== destination) destination.append(this.frameTarget)

    if (!this.mediaQuery.matches && this.inspectorDialogTarget.open) this.inspectorDialogTarget.close()
  }

  selectRow(link) {
    this.element.querySelectorAll(".observation-deck__table tr[aria-current]").forEach((row) => {
      row.removeAttribute("aria-current")
      row.classList.remove("is-selected")
    })

    const row = link.closest("tr")
    if (!row) return

    row.setAttribute("aria-current", "true")
    row.classList.add("is-selected")
  }

  restoreTheme() {
    let theme = "system"

    try {
      theme = localStorage.getItem("observation-deck-theme") || theme
    } catch (_) {
      // Browser privacy settings can block storage; system remains usable.
    }

    this.applyTheme(theme, false)
  }

  applyTheme(theme, persist = true) {
    const selectedTheme = ["system", "light", "dark"].includes(theme) ? theme : "system"
    document.documentElement.dataset.observationDeckTheme = selectedTheme
    this.themeOptionTargets.forEach((option) => { option.checked = option.value === selectedTheme })

    if (!persist) return

    try {
      localStorage.setItem("observation-deck-theme", selectedTheme)
    } catch (_) {
      // Browser privacy settings can block storage; selected theme still applies.
    }
  }

  updateSystemTheme() {
    if (document.documentElement.dataset.observationDeckTheme === "system") this.applyTheme("system", false)
  }
}
