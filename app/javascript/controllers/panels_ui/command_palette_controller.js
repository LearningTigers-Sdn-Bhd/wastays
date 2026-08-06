import { Controller } from "@hotwired/stimulus"

// Identifier: panels-ui--command-palette
//
// Owns the trigger, the global ⌘K / "/" shortcut, the debounced async search,
// the listbox keyboard navigation, and navigate-on-select. Overlay concerns —
// scroll-lock, backdrop dismissal, Escape, focus-trapping and the top layer —
// belong to the nested `panels-ui--dialog` controller on the <dialog> element
// and to the native <dialog> itself, so none of that is re-implemented here.
export default class extends Controller {
  static targets = ["dialog", "input", "results", "empty", "shortcut", "loading", "scroll"]
  static values = { endpoint: String }

  connect() {
    this.resultsData = []
    this.quickActionsData = []
    this.activeIndex = -1
    this.currentQuery = ""
    this.searchTimer = null
    this.abortController = null
    this.prefetched = null
    this.prefetchController = null
    this.updateShortcutLabel()
    this.onGlobalKeydown = this.onGlobalKeydown.bind(this)
    window.addEventListener("keydown", this.onGlobalKeydown)
    this.prefetch()
  }

  disconnect() {
    window.removeEventListener("keydown", this.onGlobalKeydown)
    if (this.searchTimer) clearTimeout(this.searchTimer)
    this.abortController?.abort()
    this.prefetchController?.abort()
  }

  // Warm the empty-query result set in the background right after connect, so the
  // very first open can paint real results instantly instead of showing the
  // skeleton for a round-trip. Best-effort: any failure is ignored and open()
  // simply falls back to a normal fetch.
  prefetch() {
    this.prefetchController = new AbortController()
    fetch(`${this.endpointValue}?q=`, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      signal: this.prefetchController.signal
    })
      .then((response) => (response.ok ? response.json() : null))
      .then((payload) => {
        if (!payload) return
        this.prefetched = { results: payload.results || [], quickActions: payload.quick_actions || [] }
      })
      .catch(() => {}) // network/abort — open() will fetch on demand
  }

  // ── Open / close ────────────────────────────────────────────────────────────
  // Opening the native <dialog> triggers the dialog controller's MutationObserver,
  // which locks scroll and marks the top overlay. We only focus the input and kick
  // off an initial (empty-query) search so the palette shows content immediately.
  open() {
    if (this.dialogTarget.open) return
    this.dialogTarget.showModal()
    this.inputTarget.focus()
    // Instant paint from the prefetch cache (empty query at open time). This
    // leaves resultsData populated, so the revalidating searchNow() below refreshes
    // in the background without showing the skeleton (stale-while-revalidate).
    if (this.prefetched) {
      this.resultsData = this.prefetched.results
      this.quickActionsData = this.prefetched.quickActions
      this.currentQuery = ""
      this.activeIndex = this.resultsData.length > 0 ? 0 : -1
      this.renderResults()
    }
    this.searchNow()
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  // Fired by the dialog's native `close` event (any close path). The dialog
  // controller already unlocked scroll; here we just clear palette state so the
  // next open starts fresh.
  reset() {
    if (this.searchTimer) clearTimeout(this.searchTimer)
    this.abortController?.abort()
    this.abortController = null
    this.inputTarget.value = ""
    this.resultsData = []
    this.quickActionsData = []
    this.activeIndex = -1
    this.currentQuery = ""
    this.renderResults()
  }

  onGlobalKeydown(event) {
    if (!event.key) return
    const key = event.key.toLowerCase()
    const commandPressed = (event.metaKey || event.ctrlKey) && key === "k"
    const slashPressed = key === "/" && !event.metaKey && !event.ctrlKey && !event.altKey

    if (commandPressed || (slashPressed && !this.isTypingField(event.target) && !this.dialogTarget.open)) {
      event.preventDefault()
      this.open()
    }
    // Escape while open is handled natively by <dialog> (cancel → close).
  }

  // ── Search ────────────────────────────────────────────────────────────────
  search() {
    if (this.searchTimer) clearTimeout(this.searchTimer)
    this.searchTimer = window.setTimeout(() => this.searchNow(), 180)
  }

  searchNow() {
    const query = this.inputTarget.value.trim()
    this.currentQuery = query

    // Cancel any in-flight request so a slow earlier response can't clobber a
    // newer one (the classic autocomplete race).
    this.abortController?.abort()
    this.abortController = new AbortController()

    // Show the skeleton only when nothing is on screen yet (first open / after a
    // reset): the panel opens with stable placeholder rows instead of flashing
    // empty → populated. On subsequent keystrokes we keep the current results
    // visible (stale-while-revalidate) and just flag busy, avoiding stutter.
    if (this.resultsData.length === 0) this.showLoading()
    else this.setBusy(true)

    const url = `${this.endpointValue}?q=${encodeURIComponent(query)}`

    fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      signal: this.abortController.signal
    })
      .then((response) => (response.ok ? response.json() : { results: [] }))
      .then((payload) => {
        this.resultsData = payload.results || []
        this.quickActionsData = payload.quick_actions || []
        this.activeIndex = this.resultsData.length > 0 ? 0 : -1
        this.renderResults()
      })
      .catch((error) => {
        if (error.name === "AbortError") return // superseded by a newer query
        this.resultsData = []
        this.quickActionsData = []
        this.activeIndex = -1
        this.renderResults()
      })
  }

  // ── Keyboard navigation ─────────────────────────────────────────────────────
  onKeydown(event) {
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
      const item = this.resultsData[this.activeIndex]
      if (item) this.navigateTo(item.url, item.external)
    }
  }

  choose(event) {
    const index = Number(event.currentTarget.dataset.index)
    const item = this.resultsData[index]
    if (item) this.navigateTo(item.url, item.external)
  }

  // Results the server marks `external` belong to another layer. The sidebar
  // opens those in a new tab, so the palette does too -- reaching the same page
  // two ways should not leave you in two different places.
  navigateTo(url, external = false) {
    if (!url) return
    this.close()
    if (external) {
      window.open(url, "_blank", "noopener")
      return
    }
    if (window.Turbo && typeof window.Turbo.visit === "function") {
      window.Turbo.visit(url)
    } else {
      window.location.href = url
    }
  }

  // ── Loading state ───────────────────────────────────────────────────────────
  showLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.hidden = false
    this.resultsTarget.hidden = true
    if (this.hasEmptyTarget) this.emptyTarget.hidden = true
    this.setBusy(true)
  }

  hideLoading() {
    if (this.hasLoadingTarget) this.loadingTarget.hidden = true
    this.resultsTarget.hidden = false
    this.setBusy(false)
  }

  setBusy(state) {
    if (this.hasScrollTarget) this.scrollTarget.setAttribute("aria-busy", state ? "true" : "false")
  }

  // ── Rendering ───────────────────────────────────────────────────────────────
  renderResults() {
    this.hideLoading()
    this.resultsTarget.replaceChildren()

    if (this.resultsData.length === 0) {
      this.emptyTarget.hidden = false
      this.inputTarget.removeAttribute("aria-activedescendant")
      return
    }

    this.emptyTarget.hidden = true
    let currentGroup = null
    const actionByGroup = new Map(
      this.quickActionsData
        .filter((action) => action.group && action.url)
        .map((action) => [action.group, action])
    )

    this.resultsData.forEach((item, index) => {
      if (item.group && item.group !== currentGroup) {
        currentGroup = item.group
        this.resultsTarget.appendChild(this.buildGroupHeader(currentGroup, actionByGroup.get(currentGroup)))
      }
      this.resultsTarget.appendChild(this.buildOption(item, index))
    })

    this.updateActiveItem()
  }

  buildGroupHeader(group, action) {
    const header = document.createElement("li")
    header.className = "panel-command-palette__group"
    header.setAttribute("role", "presentation")

    const label = document.createElement("span")
    label.className = "panel-command-palette__group-label"
    label.textContent = group
    header.appendChild(label)

    if (action) {
      const link = document.createElement("a")
      link.href = action.url
      link.className = "panel-command-palette__group-action"
      link.textContent = action.label || "Go to"
      const arrow = document.createElement("span")
      arrow.setAttribute("aria-hidden", "true")
      arrow.textContent = "→"
      link.appendChild(arrow)
      header.appendChild(link)
    }

    return header
  }

  buildOption(item, index) {
    const option = document.createElement("li")
    option.id = `${this.listboxId}-opt-${index}`
    option.dataset.index = String(index)
    option.dataset.commandPaletteItem = "true"
    option.className = "panel-command-palette__option"
    option.setAttribute("role", "option")
    option.setAttribute("aria-selected", "false")
    option.addEventListener("click", this.choose.bind(this))

    const title = document.createElement("p")
    title.className = "panel-command-palette__option-title"
    this.appendHighlighted(title, item.title || "")
    option.appendChild(title)

    if (item.subtitle) {
      const subtitle = document.createElement("p")
      subtitle.className = "panel-command-palette__option-subtitle"
      this.appendHighlighted(subtitle, item.subtitle)
      option.appendChild(subtitle)
    }

    return option
  }

  updateActiveItem() {
    const options = this.resultsTarget.querySelectorAll("[data-command-palette-item]")
    options.forEach((option, index) => {
      const active = index === this.activeIndex
      option.classList.toggle("is-active", active)
      option.setAttribute("aria-selected", active ? "true" : "false")
      if (active) {
        this.inputTarget.setAttribute("aria-activedescendant", option.id)
        option.scrollIntoView({ block: "nearest" })
      }
    })
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  get listboxId() {
    return this.resultsTarget.id
  }

  isTypingField(target) {
    if (!target) return false
    const tag = target.tagName
    return tag === "INPUT" || tag === "TEXTAREA" || target.isContentEditable
  }

  // The hint ships as the ⌘ icon + K. Only the modifier key is touched, so the
  // "+ K" half of the combination survives on every platform. Off Apple the
  // icon is replaced with the word Ctrl — assigning textContent drops the SVG.
  updateShortcutLabel() {
    if (!this.hasShortcutTarget) return
    const platform = navigator.platform || ""
    const isApple = /Mac|iPhone|iPad|iPod/.test(platform)
    if (isApple) return

    const modifierKey = this.shortcutTarget.querySelector("kbd")
    if (modifierKey) modifierKey.textContent = "Ctrl"
    this.shortcutTarget.setAttribute("aria-label", "Ctrl+K")
  }

  // Append `text` to `element` as DOM nodes, wrapping query-term matches in a
  // <mark>. Built with real text nodes (never innerHTML) so user/record content
  // can never be interpreted as markup.
  appendHighlighted(element, text) {
    const source = String(text)
    const terms = this.currentQuery
      .trim()
      .toLowerCase()
      .split(/\s+/)
      .filter((term) => term.length >= 2)

    if (terms.length === 0) {
      element.appendChild(document.createTextNode(source))
      return
    }

    const escapedTerms = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    const regex = new RegExp(`(${escapedTerms.join("|")})`, "ig")
    let lastIndex = 0

    for (const match of source.matchAll(regex)) {
      const start = match.index
      if (start > lastIndex) {
        element.appendChild(document.createTextNode(source.slice(lastIndex, start)))
      }
      const mark = document.createElement("mark")
      mark.className = "panel-command-palette__mark"
      mark.textContent = match[0]
      element.appendChild(mark)
      lastIndex = start + match[0].length
    }

    if (lastIndex < source.length) {
      element.appendChild(document.createTextNode(source.slice(lastIndex)))
    }
  }
}
