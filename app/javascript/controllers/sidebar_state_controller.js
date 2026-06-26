import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tooltip"]
  static values = { key: String }

  connect() {
    this.beforeVisitHandler = this.persistScroll.bind(this)
    this.loadHandler = this.syncAndRestore.bind(this)
    this.clickHandler = this.closeFlyoutsFromOutsideClick.bind(this)
    this.sidebarClickHandler = this.togglePinnedGroup.bind(this)
    this.keydownHandler = this.closeFlyoutsFromEscape.bind(this)
    this.toggleHandler = this.positionOpenFlyout.bind(this)
    this.stateChangeHandler = this.handleStateChange.bind(this)

    document.addEventListener("turbo:before-visit", this.beforeVisitHandler)
    document.addEventListener("turbo:load", this.loadHandler)
    document.addEventListener("click", this.clickHandler)
    document.addEventListener("keydown", this.keydownHandler)
    this.element.addEventListener("click", this.sidebarClickHandler)
    this.element.addEventListener("toggle", this.toggleHandler, true)
    this.element.addEventListener("sidebar:state-change", this.stateChangeHandler)
    this.bindHoverInteractions()

    this.syncAndRestore()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.beforeVisitHandler)
    document.removeEventListener("turbo:load", this.loadHandler)
    document.removeEventListener("click", this.clickHandler)
    document.removeEventListener("keydown", this.keydownHandler)
    this.element.removeEventListener("click", this.sidebarClickHandler)
    this.element.removeEventListener("toggle", this.toggleHandler, true)
    this.element.removeEventListener("sidebar:state-change", this.stateChangeHandler)
    this.unbindHoverInteractions()
    this.hideTooltip()
  }

  syncAndRestore() {
    this.syncActiveLinks()
    this.restoreScroll()
  }

  syncActiveLinks() {
    const currentPath = this.normalize(window.location.pathname)
    const links = Array.from(this.element.querySelectorAll("a[data-sidebar-route][href]"))
    const activeLink = links
      .filter((link) => this.pathMatches(currentPath, this.linkPath(link)))
      .sort((a, b) => this.linkPath(b).length - this.linkPath(a).length)[0]

    links.forEach((link) => {
      this.toggleActive(link, link === activeLink)
    })

    this.element.querySelectorAll("details.group").forEach((details) => {
      const hasActiveChild = Boolean(details.querySelector("a.sidebar-nav-link-active"))

      details.classList.toggle("sidebar-group-active", hasActiveChild)
      if (this.collapsed) {
        this.closeGroup(details)
      } else if (hasActiveChild) {
        details.setAttribute("open", "open")
      }
    })
  }

  pathMatches(currentPath, linkPath) {
    if (!linkPath) return false

    return currentPath === linkPath || currentPath.startsWith(`${linkPath}/`)
  }

  bindHoverInteractions() {
    this.groupInteractions = Array.from(this.element.querySelectorAll("details.sidebar-group")).map((details) => {
      const enter = () => this.openGroup(details, false)
      const leave = () => this.closeTemporaryGroup(details)
      const focusIn = () => this.openGroup(details, false)
      const focusOut = (event) => {
        if (!details.contains(event.relatedTarget)) this.closeTemporaryGroup(details)
      }

      details.addEventListener("mouseenter", enter)
      details.addEventListener("mouseleave", leave)
      details.addEventListener("focusin", focusIn)
      details.addEventListener("focusout", focusOut)

      return { details, enter, leave, focusIn, focusOut }
    })

    this.tooltipInteractions = Array.from(this.element.querySelectorAll("[data-sidebar-tooltip]")).map((trigger) => {
      const show = () => this.showTooltip(trigger)
      const hide = () => this.hideTooltip()

      trigger.addEventListener("mouseenter", show)
      trigger.addEventListener("mouseleave", hide)
      trigger.addEventListener("focus", show)
      trigger.addEventListener("blur", hide)

      return { trigger, show, hide }
    })
  }

  unbindHoverInteractions() {
    this.groupInteractions?.forEach(({ details, enter, leave, focusIn, focusOut }) => {
      details.removeEventListener("mouseenter", enter)
      details.removeEventListener("mouseleave", leave)
      details.removeEventListener("focusin", focusIn)
      details.removeEventListener("focusout", focusOut)
    })

    this.tooltipInteractions?.forEach(({ trigger, show, hide }) => {
      trigger.removeEventListener("mouseenter", show)
      trigger.removeEventListener("mouseleave", hide)
      trigger.removeEventListener("focus", show)
      trigger.removeEventListener("blur", hide)
    })
  }

  togglePinnedGroup(event) {
    const summary = event.target.closest("summary.sidebar-group-parent")
    if (!summary || !this.collapsed) return

    event.preventDefault()
    const details = summary.closest("details.sidebar-group")

    if (details.open && details.dataset.sidebarPinned === "true") {
      this.closeGroup(details)
    } else {
      this.openGroup(details, true)
    }
  }

  openGroup(details, pinned) {
    if (!details || !this.collapsed) return

    this.hideTooltip()
    this.closeFlyouts(details)
    const remainsPinned = details.dataset.sidebarPinned === "true"
    details.dataset.sidebarPinned = pinned || remainsPinned ? "true" : "false"
    details.setAttribute("open", "open")
    this.positionFlyout(details)
  }

  closeTemporaryGroup(details) {
    if (!this.collapsed) return
    if (details.dataset.sidebarPinned === "true") return
    if (details.contains(document.activeElement)) return
    if (details.matches(":hover")) return

    this.closeGroup(details)
  }

  closeGroup(details) {
    details.removeAttribute("open")
    delete details.dataset.sidebarPinned
  }

  positionOpenFlyout(event) {
    const details = event.target
    if (!(details instanceof HTMLDetailsElement) || !details.open || !this.collapsed) return

    this.closeFlyouts(details)
    this.positionFlyout(details)
  }

  positionFlyout(details) {
    const summary = details.querySelector("summary.sidebar-group-parent")
    const flyout = details.querySelector(".sidebar-details-content")
    if (!summary || !flyout) return

    const rect = summary.getBoundingClientRect()
    flyout.style.left = `${rect.right + 8}px`
    flyout.style.top = `${Math.max(8, Math.min(rect.top, window.innerHeight - flyout.offsetHeight - 8))}px`
  }

  showTooltip(trigger) {
    if (!this.hasTooltipTarget || !this.collapsed || trigger.closest("summary.sidebar-group-parent")) return

    if (!trigger.closest("details.sidebar-group")) this.closeFlyouts()
    const label = trigger.dataset.sidebarTooltip
    if (!label) return

    this.tooltipTarget.textContent = label
    this.tooltipTarget.classList.remove("hidden")

    const triggerRect = trigger.getBoundingClientRect()
    const tooltipRect = this.tooltipTarget.getBoundingClientRect()
    const top = Math.max(8, Math.min(triggerRect.top + ((triggerRect.height - tooltipRect.height) / 2), window.innerHeight - tooltipRect.height - 8))

    this.tooltipTarget.style.left = `${triggerRect.right + 8}px`
    this.tooltipTarget.style.top = `${top}px`
  }

  hideTooltip() {
    if (!this.hasTooltipTarget) return

    this.tooltipTarget.classList.add("hidden")
    this.tooltipTarget.textContent = ""
  }

  closeFlyoutsFromOutsideClick(event) {
    if (!this.collapsed || event.target.closest("details.sidebar-group")) return

    this.closeFlyouts()
    this.hideTooltip()
  }

  closeFlyoutsFromEscape(event) {
    if (event.key !== "Escape") return

    const openDetails = this.element.querySelector("details.sidebar-group[open]")
    if (!openDetails || !this.collapsed) return

    this.closeGroup(openDetails)
    this.hideTooltip()
    openDetails.querySelector("summary")?.focus()
  }

  closeFlyouts(except = null) {
    this.element.querySelectorAll("details.sidebar-group[open]").forEach((details) => {
      if (details !== except) this.closeGroup(details)
    })
  }

  handleStateChange(event) {
    if (event.detail.collapsed) this.closeFlyouts()
    this.hideTooltip()
  }

  persistScroll() {
    if (this.collapsed) this.closeFlyouts()
    this.hideTooltip()

    const desktop = this.scrollable(this.element)
    const mobile = this.scrollable(document.getElementById(`${this.keyValue}-sidebar-mobile`))

    if (desktop) sessionStorage.setItem(this.desktopScrollKey, String(desktop.scrollTop || 0))
    if (mobile) sessionStorage.setItem(this.mobileScrollKey, String(mobile.scrollTop || 0))
  }

  restoreScroll() {
    const desktop = this.scrollable(this.element)
    const mobile = this.scrollable(document.getElementById(`${this.keyValue}-sidebar-mobile`))

    this.restoreElementScroll(desktop, this.desktopScrollKey)
    this.restoreElementScroll(mobile, this.mobileScrollKey)
  }

  restoreElementScroll(element, key) {
    if (!element) return

    const saved = Number(sessionStorage.getItem(key) || 0)
    element.scrollTop = Number.isFinite(saved) ? saved : 0
  }

  toggleActive(element, active) {
    element.classList.toggle("sidebar-nav-link-active", active)
    element.classList.toggle("sidebar-nav-link-default", !active)
  }

  linkPath(link) {
    try {
      return this.normalize(new URL(link.href, window.location.origin).pathname)
    } catch (_) {
      return null
    }
  }

  scrollable(sidebar) {
    return sidebar?.querySelector(".flex-1.overflow-y-auto") || sidebar
  }

  normalize(path) {
    if (!path) return "/"
    return path.endsWith("/") && path.length > 1 ? path.slice(0, -1) : path
  }

  get collapsed() {
    return this.element.classList.contains("sidebar-collapsed")
  }

  get desktopScrollKey() {
    return `wastays:${this.keyValue}-sidebar-desktop-scroll-top`
  }

  get mobileScrollKey() {
    return `wastays:${this.keyValue}-sidebar-mobile-scroll-top`
  }
}
