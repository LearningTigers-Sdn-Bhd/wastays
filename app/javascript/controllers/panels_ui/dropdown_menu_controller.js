import { Controller } from "@hotwired/stimulus"
import { autoUpdate, computePosition, flip, offset, shift, size } from "@floating-ui/dom"

const TYPEAHEAD_TIMEOUT_MS = 500
const SUBMENU_CLOSE_DELAY_MS = 120

export default class extends Controller {
  static targets = ["trigger", "menu", "item", "selectionInput", "submenuTrigger", "submenuPanel"]
  static values = {
    placement: { type: String, default: "bottom-start" },
    offset: { type: Number, default: 6 }
  }

  connect() {
    this.cleanupPosition = null
    this.submenuCleanups = new Map()
    this.submenuOpenSources = new Map()
    this.typeahead = ""
    this.typeaheadTimer = null
    this.submenuCloseTimer = null
    this.onOtherMenuOpen = this.handleOtherMenuOpen.bind(this)
    // Shared singleton channel across floating layers (dropdown, popover): opening one
    // closes any other that's open.
    window.addEventListener("panels-ui:layer-open", this.onOtherMenuOpen)
  }

  disconnect() {
    window.removeEventListener("panels-ui:layer-open", this.onOtherMenuOpen)
    this.cancelTypeahead()
    this.cancelSubmenuClose()
    this.stopPositioning()
    this.closeAllSubmenus()
    if (this.isOpen(this.menuTarget)) this.menuTarget.hidePopover()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    this.isOpen(this.menuTarget) ? this.close() : this.open("first")
  }

  onTriggerKeydown(event) {
    const focus = event.key === "ArrowUp" ? "last" : "first"
    if (!["Enter", " ", "ArrowDown", "ArrowUp"].includes(event.key)) return

    event.preventDefault()
    this.open(focus)
  }

  open(focus = "first") {
    if (this.isOpen(this.menuTarget)) return

    window.dispatchEvent(new CustomEvent("panels-ui:layer-open", { detail: { controller: this } }))
    this.menuTarget.showPopover()
    this.triggerTarget.setAttribute("aria-expanded", "true")
    this.startPositioning(this.triggerTarget, this.menuTarget, this.placementValue)

    requestAnimationFrame(() => {
      const items = this.itemsFor(this.menuTarget)
      const target = focus === "last" ? items.at(-1) : items[0]
      target?.focus()
    })
  }

  close(restoreFocus = false) {
    this.cancelTypeahead()
    this.cancelSubmenuClose()
    this.closeAllSubmenus()
    this.stopPositioning()

    if (this.isOpen(this.menuTarget)) this.menuTarget.hidePopover()
    this.triggerTarget.setAttribute("aria-expanded", "false")
    if (restoreFocus) this.triggerTarget.focus()
  }

  onPopoverToggle(event) {
    if (event.target !== this.menuTarget || event.newState !== "closed") return

    this.triggerTarget.setAttribute("aria-expanded", "false")
    this.stopPositioning()
    this.closeAllSubmenus()
  }

  onWindowPointerDown(event) {
    if (this.isOpen(this.menuTarget) && !this.element.contains(event.target)) this.close()
  }

  handleOtherMenuOpen(event) {
    if (event.detail?.controller !== this) this.close()
  }

  onMenuKeydown(event) {
    const menu = event.target.closest('[role="menu"]')
    const item = event.target.closest('[data-panels-ui--dropdown-menu-target~="item"]')
    if (!menu || !item) return

    const items = this.itemsFor(menu)
    const index = items.indexOf(item)

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        items[(index + 1) % items.length]?.focus()
        break
      case "ArrowUp":
        event.preventDefault()
        items[(index - 1 + items.length) % items.length]?.focus()
        break
      case "Home":
        event.preventDefault()
        items[0]?.focus()
        break
      case "End":
        event.preventDefault()
        items.at(-1)?.focus()
        break
      case "ArrowRight":
        if (item.dataset.dropdownMenuKind === "submenu") {
          event.preventDefault()
          this.openSubmenu(item, true, "keyboard")
        }
        break
      case "ArrowLeft":
        if (menu.matches("[data-panels-ui--dropdown-menu-target~='submenuPanel']")) {
          event.preventDefault()
          this.closeSubmenuPanel(menu, true)
        }
        break
      case "Escape":
        event.preventDefault()
        if (menu.matches("[data-panels-ui--dropdown-menu-target~='submenuPanel']")) {
          this.closeSubmenuPanel(menu, true)
        } else {
          this.close(true)
        }
        break
      case "Tab":
        this.close()
        break
      case "Enter":
      case " ":
        event.preventDefault()
        item.click()
        break
      default:
        if (this.isPrintableCharacter(event)) this.focusByTypeahead(event, menu, items)
    }
  }

  onMenuClick(event) {
    const item = event.target.closest('[data-panels-ui--dropdown-menu-target~="item"]')
    if (!item) return

    if (item.getAttribute("aria-disabled") === "true") {
      event.preventDefault()
      event.stopImmediatePropagation()
      return
    }

    switch (item.dataset.dropdownMenuKind) {
      case "checkbox":
      case "radio":
        event.preventDefault()
        this.toggleSelection(item)
        break
      case "submenu":
        event.preventDefault()
        if (this.isSubmenuOpen(item) && this.submenuOpenSources.get(item) === "hover") {
          this.cancelSubmenuClose()
          this.submenuOpenSources.set(item, "click")
        } else {
          this.isSubmenuOpen(item) ? this.closeSubmenu(item) : this.openSubmenu(item, false, "click")
        }
        break
      default:
        this.close()
    }
  }

  toggleSelection(item) {
    const input = item.querySelector('[data-panels-ui--dropdown-menu-target~="selectionInput"]')
    if (!input) return

    if (input.type === "radio") {
      this.selectionInputTargets
        .filter(candidate => candidate.type === "radio" && candidate.name === input.name)
        .forEach(candidate => this.setSelection(candidate, candidate === input))
    } else {
      this.setSelection(input, !input.checked)
    }

    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.dispatchEvent(new Event("change", { bubbles: true }))
  }

  setSelection(input, checked) {
    input.checked = checked
    input.closest('[data-panels-ui--dropdown-menu-target~="item"]')?.setAttribute("aria-checked", checked.toString())
  }

  openSubmenuFromPointer(event) {
    if (event.currentTarget.getAttribute("aria-disabled") === "true") return
    this.cancelSubmenuClose()
    this.openSubmenu(event.currentTarget, false, "hover")
  }

  scheduleSubmenuClose(event) {
    const trigger = event.currentTarget.querySelector(':scope > [data-panels-ui--dropdown-menu-target~="submenuTrigger"]')
    if (!trigger) return
    if (this.submenuOpenSources.get(trigger) !== "hover") return

    this.cancelSubmenuClose()
    this.submenuCloseTimer = window.setTimeout(() => this.closeSubmenu(trigger), SUBMENU_CLOSE_DELAY_MS)
  }

  cancelSubmenuClose() {
    if (!this.submenuCloseTimer) return
    window.clearTimeout(this.submenuCloseTimer)
    this.submenuCloseTimer = null
  }

  openSubmenu(trigger, focusFirst, source) {
    if (trigger.getAttribute("aria-disabled") === "true") return

    const parentMenu = trigger.closest('[role="menu"]')
    this.itemsFor(parentMenu)
      .filter(candidate => candidate !== trigger && candidate.dataset.dropdownMenuKind === "submenu")
      .forEach(candidate => this.closeSubmenu(candidate))
    const panel = this.panelFor(trigger)
    if (!panel) return

    const openSource = this.isOpen(panel) && source === "hover" ? this.submenuOpenSources.get(trigger) || source : source
    if (!this.isOpen(panel)) panel.showPopover()
    trigger.setAttribute("aria-expanded", "true")
    this.submenuOpenSources.set(trigger, openSource)
    this.startSubmenuPositioning(trigger, panel)
    if (focusFirst) requestAnimationFrame(() => this.itemsFor(panel)[0]?.focus())
  }

  closeSubmenu(trigger) {
    const panel = this.panelFor(trigger)
    if (!panel) return

    this.submenuTriggerTargets
      .filter(candidate => panel.contains(candidate))
      .reverse()
      .forEach(candidate => this.hideSubmenu(candidate))
    this.hideSubmenu(trigger)
  }

  closeSubmenuPanel(panel, restoreFocus) {
    const trigger = this.submenuTriggerTargets.find(candidate => candidate.getAttribute("aria-controls") === panel.id)
    if (!trigger) return

    this.closeSubmenu(trigger)
    if (restoreFocus) trigger.focus()
  }

  closeAllSubmenus() {
    this.submenuTriggerTargets.slice().reverse().forEach(trigger => this.hideSubmenu(trigger))
  }

  isSubmenuOpen(trigger) {
    const panel = this.panelFor(trigger)
    return panel ? this.isOpen(panel) : false
  }

  panelFor(trigger) {
    return this.submenuPanelTargets.find(panel => panel.id === trigger.getAttribute("aria-controls"))
  }

  hideSubmenu(trigger) {
    const panel = this.panelFor(trigger)
    if (!panel) return

    this.stopSubmenuPositioning(panel)
    if (this.isOpen(panel)) panel.hidePopover()
    trigger.setAttribute("aria-expanded", "false")
    this.submenuOpenSources.delete(trigger)
  }

  itemsFor(menu) {
    return Array.from(menu.querySelectorAll('[data-panels-ui--dropdown-menu-target~="item"]'))
      .filter(item => item.closest('[role="menu"]') === menu)
  }

  isOpen(element) {
    return element.matches(":popover-open")
  }

  startPositioning(reference, floating, placement) {
    this.stopPositioning()
    this.cleanupPosition = autoUpdate(reference, floating, () => this.position(reference, floating, placement))
  }

  stopPositioning() {
    this.cleanupPosition?.()
    this.cleanupPosition = null
  }

  startSubmenuPositioning(reference, floating) {
    this.stopSubmenuPositioning(floating)
    const cleanup = autoUpdate(reference, floating, () => this.position(reference, floating, "right-start"))
    this.submenuCleanups.set(floating, cleanup)
  }

  stopSubmenuPositioning(floating) {
    this.submenuCleanups.get(floating)?.()
    this.submenuCleanups.delete(floating)
  }

  position(reference, floating, placement) {
    computePosition(reference, floating, {
      placement,
      strategy: "fixed",
      middleware: [
        offset(this.offsetValue),
        flip(),
        shift({ padding: 8 }),
        size({
          padding: 8,
          apply({ availableHeight, availableWidth, elements }) {
            Object.assign(elements.floating.style, {
              maxHeight: `${Math.max(96, availableHeight)}px`,
              maxWidth: `${Math.max(176, availableWidth)}px`
            })
          }
        })
      ]
    }).then(({ x, y, placement: resolvedPlacement }) => {
      Object.assign(floating.style, {
        position: "fixed",
        left: `${x}px`,
        top: `${y}px`
      })
      floating.dataset.placement = resolvedPlacement
    })
  }

  isPrintableCharacter(event) {
    return event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey
  }

  focusByTypeahead(event, menu, items) {
    event.preventDefault()
    window.clearTimeout(this.typeaheadTimer)
    this.typeahead += event.key.toLocaleLowerCase()

    const activeIndex = items.indexOf(document.activeElement)
    const ordered = [...items.slice(activeIndex + 1), ...items.slice(0, activeIndex + 1)]
    ordered.find(item => item.textContent.trim().toLocaleLowerCase().startsWith(this.typeahead))?.focus()

    this.typeaheadTimer = window.setTimeout(() => {
      this.typeahead = ""
      this.typeaheadTimer = null
    }, TYPEAHEAD_TIMEOUT_MS)
  }

  cancelTypeahead() {
    if (this.typeaheadTimer) window.clearTimeout(this.typeaheadTimer)
    this.typeaheadTimer = null
    this.typeahead = ""
  }
}
