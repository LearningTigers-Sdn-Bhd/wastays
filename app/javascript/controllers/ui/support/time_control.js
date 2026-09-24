// Shared state and interaction for PanelsUI's direct-entry + scroll-column time UI.
// Values are canonical 24-hour strings; 12-hour conversion is display-only.
export function createTimeControl({ root, min, max, minuteStep = 1, secondStep = 1, onChange = () => {}, onEnter = () => {} }) {
  const hourCycle = Number(root.dataset.hourCycle) === 12 ? 12 : 24
  const precision = root.dataset.precision === "seconds" ? "seconds" : "minutes"
  const parts = ["hours", "minutes", ...(precision === "seconds" ? ["seconds"] : []), ...(hourCycle === 12 ? ["period"] : [])]
  const state = { hours: null, minutes: null, seconds: precision === "seconds" ? null : 0, period: hourCycle === 12 ? "AM" : null }
  let activePart = parts[0]
  let typing = { part: null, digits: "" }
  let typingTimer = null

  const options = (part) => [...root.querySelectorAll(`[data-time-option="${part}"]`)]
  const selectedIndex = (part) => options(part).findIndex((option) => String(option.dataset.timeValue) === String(state[part]))

  function setValue(value) {
    const parsed = parse(value)
    if (!parsed) {
      state.hours = state.minutes = null
      if (precision === "seconds") state.seconds = null
      if (hourCycle === 12) state.period = "AM"
    } else {
      state.hours = hourCycle === 12 ? (parsed.hours % 12 || 12) : parsed.hours
      state.minutes = parsed.minutes
      state.seconds = parsed.seconds
      if (hourCycle === 12) state.period = parsed.hours >= 12 ? "PM" : "AM"
    }
    clearInvalid()
    render(false)
  }

  function canonical() {
    if (state.hours == null || state.minutes == null || (precision === "seconds" && state.seconds == null)) return ""
    let hours = Number(state.hours)
    if (hourCycle === 12) hours = (hours % 12) + (state.period === "PM" ? 12 : 0)
    const value = `${pad(hours)}:${pad(state.minutes)}${precision === "seconds" ? `:${pad(state.seconds)}` : ""}`
    return clamp(value, min, max, precision)
  }

  function commit() {
    const value = canonical()
    if (value) {
      setValue(value)
      render(true)
      onChange(value)
    } else {
      render(true)
    }
  }

  function clearInvalid() {
    root.removeAttribute("aria-invalid")
    root.querySelectorAll("[data-time-input]").forEach((input) => input.removeAttribute("aria-invalid"))
    root.querySelector("[data-time-error]").textContent = ""
  }

  function markInvalid(part) {
    root.setAttribute("aria-invalid", "true")
    root.querySelector(`[data-time-input="${part}"]`)?.setAttribute("aria-invalid", "true")
    const label = part.charAt(0).toUpperCase() + part.slice(1)
    root.querySelector("[data-time-error]").textContent = `${label} is outside the available values.`
  }

  function choose(part, value, shouldCommit = true) {
    state[part] = part === "period" ? value : Number(value)
    if (part === "hours" && state.minutes == null) state.minutes = 0
    if (part === "minutes" && state.hours == null) state.hours = hourCycle === 12 ? 12 : 0
    if (precision === "seconds" && state.seconds == null) state.seconds = 0
    activePart = part
    clearTimeout(typingTimer)
    typing = { part: null, digits: "" }
    shouldCommit ? commit() : render(true)
  }

  function render(scroll) {
    parts.forEach((part) => {
      const input = root.querySelector(`[data-time-input="${part}"]`)
      const value = state[part]
      if (input && !(typing.part === part && document.activeElement === input)) input.value = value == null ? "" : part === "period" ? value : pad(value)
      const column = root.querySelector(`[data-time-column="${part}"]`)
      if (column) column.dataset.active = String(part === activePart)
      const listbox = root.querySelector(`[data-time-listbox="${part}"]`)
      options(part).forEach((option) => {
        const selected = String(option.dataset.timeValue) === String(state[part])
        option.setAttribute("aria-selected", String(selected))
        option.dataset.active = String(part === activePart)
        if (selected) {
          listbox?.setAttribute("aria-activedescendant", option.id)
          if (scroll && root.offsetParent) alignOption(option)
        }
      })
    })
    root.dataset.activePart = activePart
    const value = canonical()
    root.querySelector("[data-time-status]").textContent = value ? `Time ${format(value, hourCycle)}` : "Time incomplete"
  }

  function scrollSelected() {
    parts.forEach((part) => {
      const option = root.querySelector(`[data-time-option="${part}"][aria-selected="true"]`)
      if (option) alignOption(option)
    })
  }

  function alignOption(option) {
    const viewport = option.closest(".panel-time-control__viewport")
    if (!viewport) return
    const preferred = option.previousElementSibling?.offsetTop ?? option.offsetTop
    const target = Math.max(0, Math.min(preferred, viewport.scrollHeight - viewport.clientHeight))
    viewport.scrollTo({ top: target, behavior: "instant" })
  }

  function onClick(event) {
    const option = event.target.closest("[data-time-option]")
    if (option) choose(option.dataset.timeOption, option.dataset.timeValue)
  }

  function onFocusIn(event) {
    const part = event.target.dataset.timeInput || event.target.dataset.timeOption
    if (!part) return
    activePart = part
    render(false)
  }

  function onFocusOut(event) {
    const input = event.target.closest("[data-time-input]")
    if (!input || input.disabled) return
    commitInput(input)
  }

  function onInput(event) {
    const input = event.target.closest("[data-time-input]")
    if (!input || input.disabled) return
    const part = input.dataset.timeInput
    const digits = input.value.replace(/\D/g, "").slice(0, 2)
    input.value = digits
    activePart = part
    clearInvalid()
    clearTimeout(typingTimer)
    typing = { part, digits }
    if (!digits) {
      state[part] = null
      render(false)
      return
    }
    const exact = options(part).find((option) => Number(option.dataset.timeValue) === Number(digits))
    if (digits.length === 2) {
      if (exact) choose(part, exact.dataset.timeValue)
      else markInvalid(part)
      return
    }
    if (exact) {
      state[part] = Number(exact.dataset.timeValue)
      render(false)
      input.value = digits
      typingTimer = window.setTimeout(() => commitInput(input), 700)
    } else if (options(part).some((option) => option.dataset.timeValue.padStart(2, "0").startsWith(digits))) {
      render(false)
      input.value = digits
    } else {
      markInvalid(part)
    }
  }

  function commitInput(input) {
    const part = input.dataset.timeInput
    const digits = input.value.replace(/\D/g, "").slice(0, 2)
    const exact = options(part).find((option) => Number(option.dataset.timeValue) === Number(digits))
    clearTimeout(typingTimer)
    if (digits && exact) choose(part, exact.dataset.timeValue)
    else if (digits) markInvalid(part)
    else render(false)
  }

  function onKeydown(event) {
    const input = event.target.closest("[data-time-input]")
    if (input && !input.disabled) {
      activePart = input.dataset.timeInput
      if (event.key === "Enter") { event.preventDefault(); commitInput(input); return }
      if (["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key)) {
        event.preventDefault()
        stepPart(activePart, event.key)
      }
      return
    }
    if (event.key === "Enter") { event.preventDefault(); onEnter(); return }
    const columnIndex = parts.indexOf(activePart)
    if (event.key === "ArrowLeft" || event.key === "ArrowRight") {
      event.preventDefault()
      activePart = parts[Math.max(0, Math.min(parts.length - 1, columnIndex + (event.key === "ArrowRight" ? 1 : -1)))]
      render(true); return
    }
    const values = options(activePart).map((option) => option.dataset.timeValue)
    if (["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(event.key)) {
      event.preventDefault()
      stepPart(activePart, event.key); return
    }
    if (activePart === "period" && /^[ap]$/i.test(event.key)) { event.preventDefault(); choose(activePart, event.key.toLowerCase() === "a" ? "AM" : "PM"); return }
    if (/^\d$/.test(event.key) && activePart !== "period") {
      event.preventDefault()
      const digits = typing.part === activePart ? typing.digits + event.key : event.key
      typing = { part: activePart, digits: digits.slice(-2) }
      clearTimeout(typingTimer)
      const exact = values.find((value) => Number(value) === Number(typing.digits))
      if (typing.digits.length === 2) {
        if (exact != null) choose(activePart, exact)
        else markInvalid(activePart)
      } else if (exact != null) {
        state[activePart] = Number(exact)
        render(false)
        typingTimer = window.setTimeout(() => { typing = { part: null, digits: "" }; commit() }, 700)
      }
    }
  }

  function stepPart(part, key) {
    const values = options(part).map((option) => option.dataset.timeValue)
    let index = selectedIndex(part)
    if (key === "Home") index = 0
    else if (key === "End") index = values.length - 1
    else {
      const delta = key === "ArrowUp" ? -1 : key === "ArrowDown" ? 1 : key === "PageUp" ? -5 : 5
      index = (Math.max(index, 0) + delta + values.length) % values.length
    }
    choose(part, values[index])
  }

  render(false)
  return { setValue, getValue: canonical, formatValue: (value) => format(value, hourCycle), onClick, onInput, onFocusIn, onFocusOut, onKeydown, scrollSelected, focus: () => root.querySelector("[data-time-input]:not(:disabled)")?.focus(), destroy() { clearTimeout(typingTimer) } }
}

function parse(value) {
  const match = String(value || "").match(/^(\d{1,2}):(\d{2})(?::(\d{2}))?/)
  if (!match) return null
  return { hours: Number(match[1]), minutes: Number(match[2]), seconds: Number(match[3] || 0) }
}
function seconds(value) { const p = parse(value); return p ? p.hours * 3600 + p.minutes * 60 + p.seconds : null }
function clamp(value, min, max, precision) {
  let total = seconds(value)
  const lower = seconds(min); const upper = seconds(max)
  if (lower != null) total = Math.max(total, lower)
  if (upper != null) total = Math.min(total, upper)
  const h = Math.floor(total / 3600); const m = Math.floor(total % 3600 / 60); const s = total % 60
  return `${pad(h)}:${pad(m)}${precision === "seconds" ? `:${pad(s)}` : ""}`
}
function format(value, hourCycle) {
  const p = parse(value); if (!p) return ""
  const suffix = hourCycle === 12 ? ` ${p.hours >= 12 ? "PM" : "AM"}` : ""
  const hour = hourCycle === 12 ? p.hours % 12 || 12 : p.hours
  return `${pad(hour)}:${pad(p.minutes)}${value.split(":").length === 3 ? `:${pad(p.seconds)}` : ""}${suffix}`
}
function pad(value) { return String(value).padStart(2, "0") }
