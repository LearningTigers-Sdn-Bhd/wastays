import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "listbox", "status"]
  static values = {
    endpoint: String,
    minLength: { type: Number, default: 2 },
    debounce: { type: Number, default: 180 },
    emptyText: { type: String, default: "No matching results" }
  }

  connect() {
    this.results = []
    this.activeIndex = -1
    this.timer = null
    this.abortController = null
  }

  disconnect() {
    if (this.timer) clearTimeout(this.timer)
    this.abortController?.abort()
  }

  search(event) {
    // External controllers may populate the field after a selection. Those
    // synthetic input events keep normal form listeners informed but should not
    // immediately reopen every autocomplete with another request.
    if (event && !event.isTrusted) return
    if (this.timer) clearTimeout(this.timer)
    this.results = []
    this.activeIndex = -1
    this.close()
    this.timer = window.setTimeout(() => this.searchNow(), this.debounceValue)
  }

  open() {
    if (this.inputTarget.disabled || this.inputTarget.readOnly) return
    if (this.results.length > 0) this.showListbox()
    else if (this.inputTarget.value.trim().length >= this.minLengthValue) this.searchNow()
  }

  async searchNow() {
    const query = this.inputTarget.value.trim()
    this.abortController?.abort()
    if (query.length < this.minLengthValue) {
      this.results = []
      this.close()
      this.announce("")
      return
    }

    const requestController = new AbortController()
    this.abortController = requestController
    this.inputTarget.setAttribute("aria-busy", "true")
    this.announce("Searching")

    try {
      const url = new URL(this.endpointValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
        signal: requestController.signal
      })
      if (!response.ok) throw new Error(`Autocomplete request failed: ${response.status}`)

      const payload = await response.json()
      this.results = Array.isArray(payload.results) ? payload.results : []
      this.activeIndex = this.results.length > 0 ? 0 : -1
      this.renderResults()
    } catch (error) {
      if (error.name === "AbortError") return
      this.results = []
      this.activeIndex = -1
      this.renderMessage("Suggestions could not be loaded")
      this.announce("Suggestions could not be loaded")
    } finally {
      if (this.abortController === requestController) this.inputTarget.removeAttribute("aria-busy")
    }
  }

  renderResults() {
    this.listboxTarget.replaceChildren()
    if (this.results.length === 0) {
      this.renderMessage(this.emptyTextValue)
      this.announce(this.emptyTextValue)
      return
    }

    this.results.forEach((result, index) => {
      const option = document.createElement("div")
      option.id = `${this.inputTarget.id}-autocomplete-option-${index}`
      option.className = "panel-autocomplete__option"
      option.setAttribute("role", "option")
      option.setAttribute("aria-selected", index === this.activeIndex ? "true" : "false")
      option.dataset.index = index

      const label = document.createElement("span")
      label.className = "panel-autocomplete__label"
      label.textContent = result.label || ""
      option.append(label)

      if (result.description) {
        const description = document.createElement("span")
        description.className = "panel-autocomplete__description"
        description.textContent = result.description
        option.append(description)
      }

      this.listboxTarget.append(option)
    })

    this.showListbox()
    this.updateActiveOption()
    this.announce(`${this.results.length} suggestion${this.results.length === 1 ? "" : "s"} available`)
  }

  renderMessage(message) {
    const empty = document.createElement("div")
    empty.className = "panel-autocomplete__empty"
    empty.textContent = message
    this.listboxTarget.replaceChildren(empty)
    this.showListbox()
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  onKeydown(event) {
    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (this.results.length === 0) return this.open()
      this.activeIndex = (this.activeIndex + 1) % this.results.length
      this.updateActiveOption()
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      if (this.results.length === 0) return this.open()
      this.activeIndex = (this.activeIndex - 1 + this.results.length) % this.results.length
      this.updateActiveOption()
    } else if (event.key === "Home" && !this.listboxTarget.hidden) {
      event.preventDefault()
      this.activeIndex = 0
      this.updateActiveOption()
    } else if (event.key === "End" && !this.listboxTarget.hidden) {
      event.preventDefault()
      this.activeIndex = this.results.length - 1
      this.updateActiveOption()
    } else if (event.key === "Enter" && !this.listboxTarget.hidden && this.activeIndex >= 0) {
      event.preventDefault()
      this.selectResult(this.activeIndex)
    } else if (event.key === "Escape") {
      event.preventDefault()
      this.close()
    } else if (event.key === "Tab") {
      this.close()
    }
  }

  onOptionPointerDown(event) {
    if (event.target.closest("[role='option']")) event.preventDefault()
  }

  choose(event) {
    const option = event.target.closest("[role='option']")
    if (option) this.selectResult(Number(option.dataset.index))
  }

  selectResult(index) {
    const result = this.results[index]
    if (!result) return

    this.inputTarget.value = result.label || ""
    this.inputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.inputTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.element.dispatchEvent(new CustomEvent("panels-ui:autocomplete-select", {
      bubbles: true,
      detail: { result }
    }))
    this.results = []
    this.activeIndex = -1
    this.close()
    this.announce(`${result.label || "Result"} selected`)
  }

  updateActiveOption() {
    const options = Array.from(this.listboxTarget.querySelectorAll("[role='option']"))
    options.forEach((option, index) => option.setAttribute("aria-selected", index === this.activeIndex ? "true" : "false"))
    const active = options[this.activeIndex]
    if (active) {
      this.inputTarget.setAttribute("aria-activedescendant", active.id)
      active.scrollIntoView({ block: "nearest" })
    }
  }

  showListbox() {
    this.listboxTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.listboxTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  onWindowPointerDown(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  announce(message) {
    this.statusTarget.textContent = message
  }
}
