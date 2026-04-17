import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["overlay", "input", "results", "empty"]
  static values = {
    endpoint: String
  }

  connect() {
    this.resultsData = []
    this.activeIndex = -1
    this.currentQuery = ""
    this.searchTimer = null
    this.handleGlobalKeydown = this.onGlobalKeydown.bind(this)
    window.addEventListener("keydown", this.handleGlobalKeydown)
  }

  disconnect() {
    window.removeEventListener("keydown", this.handleGlobalKeydown)
    if (this.searchTimer) clearTimeout(this.searchTimer)
  }

  onGlobalKeydown(event) {
    const key = event.key.toLowerCase()
    const commandPressed = (event.metaKey || event.ctrlKey) && key === "k"
    const slashPressed = key === "/" && !event.metaKey && !event.ctrlKey && !event.altKey

    if (commandPressed || (slashPressed && !this.isTypingField(event.target) && !this.isOpen())) {
      event.preventDefault()
      this.open()
      return
    }

    if (event.key === "Escape" && this.isOpen()) {
      event.preventDefault()
      this.close()
    }
  }

  open() {
    this.overlayTarget.classList.remove("hidden")
    this.inputTarget.focus()
    this.searchNow()
  }

  close() {
    this.overlayTarget.classList.add("hidden")
    this.inputTarget.value = ""
    this.resultsData = []
    this.activeIndex = -1
    this.currentQuery = ""
    this.renderResults()
  }

  closeOnBackdrop(event) {
    if (event.target === this.overlayTarget) this.close()
  }

  search() {
    if (this.searchTimer) clearTimeout(this.searchTimer)
    this.searchTimer = window.setTimeout(() => this.searchNow(), 180)
  }

  searchNow() {
    const query = this.inputTarget.value.trim()
    this.currentQuery = query
    const url = `${this.endpointValue}?q=${encodeURIComponent(query)}`

    fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
      .then((response) => response.ok ? response.json() : { results: [] })
      .then((payload) => {
        this.resultsData = payload.results || []
        this.activeIndex = this.resultsData.length > 0 ? 0 : -1
        this.renderResults()
      })
      .catch(() => {
        this.resultsData = []
        this.activeIndex = -1
        this.renderResults()
      })
  }

  navigateResults(event) {
    if (!this.isOpen()) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (this.resultsData.length === 0) return
      this.activeIndex = (this.activeIndex + 1) % this.resultsData.length
      this.updateActiveItem()
      return
    }

    if (event.key === "ArrowUp") {
      event.preventDefault()
      if (this.resultsData.length === 0) return
      this.activeIndex = (this.activeIndex - 1 + this.resultsData.length) % this.resultsData.length
      this.updateActiveItem()
      return
    }

    if (event.key === "Enter") {
      event.preventDefault()
      if (this.activeIndex < 0 || !this.resultsData[this.activeIndex]) return
      window.location.href = this.resultsData[this.activeIndex].url
      this.close()
    }
  }

  choose(event) {
    const index = Number(event.currentTarget.dataset.index)
    const item = this.resultsData[index]
    if (!item) return
    window.location.href = item.url
    this.close()
  }

  renderResults() {
    this.resultsTarget.innerHTML = ""

    if (this.resultsData.length === 0) {
      this.emptyTarget.classList.remove("hidden")
      return
    }

    this.emptyTarget.classList.add("hidden")
    let currentGroup = null
    this.resultsData.forEach((item, index) => {
      if (item.group && item.group !== currentGroup) {
        currentGroup = item.group
        const groupLabel = document.createElement("p")
        groupLabel.className = "px-3 pt-2 pb-1 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground-2"
        groupLabel.textContent = currentGroup
        this.resultsTarget.appendChild(groupLabel)
      }

      const button = document.createElement("button")
      button.type = "button"
      button.dataset.index = String(index)
      button.dataset.commandPaletteItem = "true"
      button.className = "w-full rounded-lg px-3 py-2.5 text-left transition-colors hover:bg-surface-hover focus:outline-none"
      button.addEventListener("click", this.choose.bind(this))

      const title = document.createElement("p")
      title.className = "text-sm font-semibold text-neutral-text-primary"
      title.innerHTML = this.highlightText(item.title || "")

      const subtitle = document.createElement("p")
      subtitle.className = "text-xs text-muted-foreground mt-0.5"
      subtitle.innerHTML = this.highlightText(item.subtitle || "")

      button.appendChild(title)
      button.appendChild(subtitle)
      this.resultsTarget.appendChild(button)
    })

    this.updateActiveItem()
  }

  updateActiveItem() {
    const items = this.resultsTarget.querySelectorAll("[data-command-palette-item]")
    items.forEach((item, index) => {
      item.classList.toggle("bg-surface-hover", index === this.activeIndex)
    })
  }

  isTypingField(target) {
    if (!target) return false
    const tag = target.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable
  }

  isOpen() {
    return !this.overlayTarget.classList.contains("hidden")
  }

  highlightText(text) {
    const safeText = this.escapeHtml(String(text))
    const terms = this.currentQuery
      .trim()
      .toLowerCase()
      .split(/\s+/)
      .filter((term) => term.length >= 2)

    if (terms.length === 0) return safeText

    const escapedTerms = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    const regex = new RegExp(`(${escapedTerms.join("|")})`, "ig")
    return safeText.replace(regex, '<mark class="rounded bg-amber-100 px-0.5 text-neutral-text-primary">$1</mark>')
  }

  escapeHtml(value) {
    return value
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#039;")
  }
}
