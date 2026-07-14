import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link", "section", "navigation", "mobileMenu"]

  connect() {
    this.activeAnchor = null
    this.pendingAnchor = null
    this.syncFrame = null
    this.revealFrame = null
    this.navigationTimer = null
    this.scheduleSync = this.scheduleSync.bind(this)
    this.handleResize = this.handleResize.bind(this)
    this.handleHistoryNavigation = this.handleHistoryNavigation.bind(this)
    this.finishNavigation = this.finishNavigation.bind(this)

    window.addEventListener("scroll", this.scheduleSync, { passive: true })
    window.addEventListener("resize", this.handleResize)
    window.addEventListener("scrollend", this.finishNavigation)
    window.addEventListener("popstate", this.handleHistoryNavigation)

    const initialAnchor = window.location.hash.slice(1)
    if (this.sectionTargets.some((section) => section.id === initialAnchor)) {
      this.startNavigation(initialAnchor)
      this.setActive(initialAnchor, false)
    }
    this.scheduleSync()
  }

  disconnect() {
    window.removeEventListener("scroll", this.scheduleSync)
    window.removeEventListener("resize", this.handleResize)
    window.removeEventListener("scrollend", this.finishNavigation)
    window.removeEventListener("popstate", this.handleHistoryNavigation)
    if (this.syncFrame) cancelAnimationFrame(this.syncFrame)
    if (this.revealFrame) cancelAnimationFrame(this.revealFrame)
    if (this.navigationTimer) window.clearTimeout(this.navigationTimer)
  }

  navigate(event) {
    const hash = event.currentTarget.hash
    const target = document.getElementById(hash.slice(1))
    if (!target) return

    event.preventDefault()
    if (this.hasMobileMenuTarget) this.mobileMenuTarget.open = false
    if (window.location.hash !== hash) window.history.pushState(window.history.state, "", hash)

    this.startNavigation(target.id)
    this.setActive(target.id, false)
    target.focus({ preventScroll: true })
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" })
  }

  revealActive() {
    if (this.hasMobileMenuTarget && this.mobileMenuTarget.open) this.scheduleReveal()
  }

  handleResize() {
    this.scheduleSync()
    this.scheduleReveal()
  }

  handleHistoryNavigation() {
    const anchor = window.location.hash.slice(1)
    if (this.sectionTargets.some((section) => section.id === anchor)) {
      this.startNavigation(anchor)
      this.setActive(anchor, false)
    } else {
      this.pendingAnchor = null
      if (this.navigationTimer) window.clearTimeout(this.navigationTimer)
      this.navigationTimer = null
      this.scheduleSync()
    }
  }

  startNavigation(anchor) {
    this.pendingAnchor = anchor
    if (this.navigationTimer) window.clearTimeout(this.navigationTimer)
    this.navigationTimer = window.setTimeout(this.finishNavigation, 1200)
  }

  scheduleSync() {
    if (this.syncFrame) return
    this.syncFrame = requestAnimationFrame(() => this.sync())
  }

  sync() {
    this.syncFrame = null
    if (!this.hasSectionTarget) return
    if (this.pendingAnchor) {
      this.setActive(this.pendingAnchor, false)
      return
    }

    const marker = window.innerHeight * 0.25
    const positions = this.sectionTargets.map((section) => ({
      anchor: section.id,
      top: section.getBoundingClientRect().top
    }))
    let active = positions[0].anchor

    positions.forEach((position) => {
      if (position.top <= marker) active = position.anchor
    })

    const atPageEnd = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2
    if (atPageEnd) active = positions[positions.length - 1].anchor

    this.setActive(active, true)
  }

  finishNavigation() {
    if (!this.pendingAnchor) return
    const target = document.getElementById(this.pendingAnchor)
    const targetRect = target?.getBoundingClientRect()
    const targetIsVisible = targetRect && targetRect.bottom > 0 && targetRect.top < window.innerHeight
    const targetMargin = target ? Number.parseFloat(window.getComputedStyle(target).scrollMarginTop) || 0 : 0
    const targetReachedPosition = targetRect && Math.abs(targetRect.top - targetMargin) <= 2
    const atPageEnd = window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2

    if (this.syncFrame) cancelAnimationFrame(this.syncFrame)
    this.syncFrame = null
    this.pendingAnchor = null
    if (this.navigationTimer) window.clearTimeout(this.navigationTimer)
    this.navigationTimer = null
    if (!targetReachedPosition && !(atPageEnd && targetIsVisible)) this.scheduleSync()
  }

  setActive(anchor, updateUrl) {
    if (this.activeAnchor === anchor) {
      if (updateUrl) this.replaceHash(anchor)
      return
    }

    this.activeAnchor = anchor
    this.linkTargets.forEach((link) => {
      if (link.dataset.previewAnchor === anchor) {
        link.setAttribute("aria-current", "location")
      } else {
        link.removeAttribute("aria-current")
      }
    })

    if (updateUrl) this.replaceHash(anchor)
    this.scheduleReveal()
  }

  replaceHash(anchor) {
    const hash = `#${anchor}`
    if (window.location.hash !== hash) window.history.replaceState(window.history.state, "", hash)
  }

  scheduleReveal() {
    if (this.revealFrame) cancelAnimationFrame(this.revealFrame)
    this.revealFrame = requestAnimationFrame(() => this.revealActiveLinks())
  }

  revealActiveLinks() {
    this.revealFrame = null
    if (!this.activeAnchor) return

    const adjustments = this.navigationTargets.filter((navigation) => navigation.offsetParent !== null).map((navigation) => {
      const link = this.linkTargets.find((candidate) => (
        navigation.contains(candidate) && candidate.dataset.previewAnchor === this.activeAnchor
      ))
      if (!link) return null

      const navigationRect = navigation.getBoundingClientRect()
      const linkRect = link.getBoundingClientRect()
      if (linkRect.top < navigationRect.top) return { navigation, delta: linkRect.top - navigationRect.top }
      if (linkRect.bottom > navigationRect.bottom) return { navigation, delta: linkRect.bottom - navigationRect.bottom }
      return null
    }).filter(Boolean)

    adjustments.forEach(({ navigation, delta }) => { navigation.scrollTop += delta })
    this.navigationTargets.filter((navigation) => navigation.offsetParent !== null).forEach((navigation) => {
      navigation.dataset.activeAnchor = this.activeAnchor
    })
  }
}
