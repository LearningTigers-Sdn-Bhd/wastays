import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]
  static values = {
    position: { type: String, default: "top-right" },
    layout: { type: String, default: "default" },
    gap: { type: Number, default: 14 },
    autoDismissDuration: { type: Number, default: 4000 },
    limit: { type: Number, default: 3 }
  }

  connect() {
    this.toasts = []
    this.timers = new Map()
    this.expanded = this.layoutValue === "expanded"
    this.boundShowToast = this.showToast.bind(this)
    this.boundDismissToast = this.dismissToast.bind(this)
    this.boundBeforeCache = this.beforeCache.bind(this)

    window.toast = this.boundShowToast
    window.dismissToast = this.boundDismissToast
    document.addEventListener("turbo:before-cache", this.boundBeforeCache)
    this.updatePosition()
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.boundBeforeCache)
    if (window.toast === this.boundShowToast) delete window.toast
    if (window.dismissToast === this.boundDismissToast) delete window.dismissToast
    this.clearAll()
  }

  showToast(message, options = {}) {
    if (!this.hasContainerTarget || !message) return null

    const toast = {
      id: `toast-${crypto.randomUUID()}`,
      message: String(message),
      description: options.description ? String(options.description) : "",
      type: this.normalizeType(options.type),
      action: options.action || null,
      secondaryAction: options.secondaryAction || null,
      duration: options.duration === false ? false : Number(options.duration || this.autoDismissDurationValue)
    }

    if (options.position) {
      this.positionValue = options.position
      this.updatePosition()
    }

    this.toasts.unshift(toast)
    while (this.toasts.length > this.limitValue) this.removeToast(this.toasts[this.toasts.length - 1].id, true)

    const element = this.createToastElement(toast)
    this.containerTarget.insertBefore(element, this.containerTarget.firstChild)
    requestAnimationFrame(() => {
      element.dataset.mounted = "true"
      this.updateStack()
      if (toast.duration > 0) this.timers.set(toast.id, window.setTimeout(() => this.removeToast(toast.id), toast.duration))
    })
    return toast.id
  }

  dismissToast(id) {
    if (id) this.removeToast(id)
  }

  handleMouseEnter() { this.setExpanded(true) }
  handleMouseLeave() { this.setExpanded(false) }

  removeToast(id, immediate = false) {
    const index = this.toasts.findIndex((toast) => toast.id === id)
    if (index < 0) return

    const element = document.getElementById(id)
    const timer = this.timers.get(id)
    if (timer) window.clearTimeout(timer)
    this.timers.delete(id)
    this.toasts.splice(index, 1)

    const finish = () => {
      element?.remove()
      this.updateStack()
    }
    if (immediate || !element || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      finish()
    } else {
      element.dataset.leaving = "true"
      element.addEventListener("transitionend", finish, { once: true })
      window.setTimeout(finish, 250)
    }
  }

  createToastElement(toast) {
    const item = document.createElement("li")
    item.id = toast.id
    item.className = "toast"
    item.dataset.variant = toast.type
    item.dataset.mounted = "false"
    item.setAttribute("role", toast.type === "error" || toast.type === "danger" ? "alert" : "status")
    item.setAttribute("aria-live", toast.type === "error" || toast.type === "danger" ? "assertive" : "polite")
    item.setAttribute("aria-atomic", "true")

    if (toast.type !== "default") {
      const icon = document.createElement("span")
      icon.className = "toast__icon"
      icon.dataset.variant = toast.type
      icon.setAttribute("aria-hidden", "true")
      const iconTemplate = this.element.querySelector(`[data-toast-icon-template="${toast.type}"]`)
      if (iconTemplate) icon.append(iconTemplate.content.cloneNode(true))
      item.append(icon)
    }

    const content = document.createElement("div")
    content.className = "toast__content"
    const title = document.createElement("p")
    title.className = "toast__title"
    title.textContent = toast.message
    content.append(title)
    if (toast.description) {
      const description = document.createElement("p")
      description.className = "toast__description"
      description.textContent = toast.description
      content.append(description)
    }
    item.append(content)

    this.appendAction(item, toast.action, "primary", toast.id)
    this.appendAction(item, toast.secondaryAction, "secondary", toast.id)

    const dismiss = document.createElement("button")
    dismiss.type = "button"
    dismiss.className = "toast__dismiss"
    dismiss.setAttribute("aria-label", "Dismiss notification")
    dismiss.innerHTML = '<span aria-hidden="true">&times;</span>'
    dismiss.addEventListener("click", () => this.removeToast(toast.id))
    item.append(dismiss)
    return item
  }

  appendAction(item, action, kind, id) {
    if (!action?.label || typeof action.onClick !== "function") return
    const button = document.createElement("button")
    button.type = "button"
    button.className = `toast__action-button toast__action-button--${kind}`
    button.textContent = action.label
    button.addEventListener("click", () => {
      action.onClick()
      this.removeToast(id)
    })
    item.append(button)
  }

  setExpanded(expanded) {
    if (this.layoutValue === "expanded") return
    this.expanded = expanded
    this.updateStack()
  }

  updatePosition() {
    if (this.hasContainerTarget) this.containerTarget.dataset.position = this.positionValue
  }

  updateStack() {
    if (!this.hasContainerTarget) return
    const direction = this.positionValue.startsWith("bottom") ? -1 : 1
    let offset = 0
    this.toasts.forEach((toast, index) => {
      const element = document.getElementById(toast.id)
      if (!element) return
      const height = element.getBoundingClientRect().height || 76
      const visible = this.expanded || index < this.limitValue
      element.dataset.index = index
      element.dataset.expanded = String(this.expanded)
      element.style.transform = `translateY(${direction * offset}px) scale(${this.expanded ? 1 : Math.max(0.94, 1 - index * 0.03)})`
      element.style.opacity = visible ? String(Math.max(0.45, 1 - index * 0.15)) : "0"
      element.style.zIndex = String(this.toasts.length - index)
      offset += this.expanded ? height + this.gapValue : 10
    })
    this.containerTarget.style.height = `${this.expanded ? Math.max(offset - this.gapValue, 0) : (this.toasts[0] ? document.getElementById(this.toasts[0].id)?.getBoundingClientRect().height || 76 : 0)}px`
  }

  beforeCache() { this.clearAll() }

  clearAll() {
    this.timers?.forEach((timer) => window.clearTimeout(timer))
    this.timers?.clear()
    this.toasts = []
    if (this.hasContainerTarget) this.containerTarget.replaceChildren()
  }

  normalizeType(type) {
    return ["default", "primary", "info", "success", "warning", "error", "danger", "loading"].includes(type) ? type : "default"
  }
}
