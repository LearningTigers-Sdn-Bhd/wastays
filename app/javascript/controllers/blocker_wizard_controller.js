import { Controller } from "@hotwired/stimulus"

const STEP_INFO = {
  due_out_not_checked_out: {
    title: "Due Outs Not Checked Out",
    description: "Guests who are scheduled to depart today but have not yet checked out."
  },
  checked_in_missing_timestamp: {
    title: "Missing Check-In Timestamps",
    description: "In-house bookings that are missing their check-in date/time stamp."
  },
  completed_missing_timestamp: {
    title: "Missing Check-Out Timestamps",
    description: "Completed bookings that are missing their check-out date/time stamp."
  },
  missing_folio: {
    title: "Missing Folios",
    description: "Bookings that require a folio structure before the business day can close."
  },
  missing_nightly_charges: {
    title: "Missing Nightly Charges",
    description: "In-house booking folios that are missing nightly room accommodation or tax charges."
  },
  outstanding_folio_balance: {
    title: "Outstanding Folio Balances",
    description: "Checked-out or departing bookings that have non-zero outstanding folio balances."
  },
  captured_payment_not_synced: {
    title: "Unsynced Captured Payments",
    description: "Payments captured by the payment gateway but not yet posted/synced to the booking folio."
  },
  refund_not_synced: {
    title: "Unsynced Completed Refunds",
    description: "Refunds processed via gateway but not yet posted/synced to the booking folio."
  },
  open_housekeeping_requests: {
    title: "Open Housekeeping Requests",
    description: "Active housekeeping tasks that are still open."
  },
  open_complaint_requests: {
    title: "Open Complaint Requests",
    description: "Active guest complaints that have not been resolved."
  },
  folio_balance_exceptions: {
    title: "Unusual Folio Balances",
    description: "In-house folios with balance anomalies (very high balance or credit balance)."
  }
}

export default class extends Controller {
  static targets = [
    "progressBar",
    "progressText",
    "stepTitle",
    "stepDescription",
    "stepTableHeader",
    "stepTableBody",
    "stepTableContainer",
    "wizardContainer",
    "completionContainer",
    "countdownContainer",
    "countdownTimer",
    "skipButton",
    "warningBadge",
    "stepIndicator"
  ]

  static values = {
    pollUrl: String,
    hotelId: Number,
    steps: Array,
    warningSteps: Array
  }

  connect() {
    this.currentStepIndex = 0
    this.countdownActive = false
    this.countdownInterval = null
    this.countdownSeconds = 3

    // Start polling
    this.poll()
    this.startPolling()

    // Page Visibility API
    this.visibilityHandler = this.handleVisibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.visibilityHandler)
  }

  disconnect() {
    this.stopPolling()
    this.stopCountdown()
    document.removeEventListener("visibilitychange", this.visibilityHandler)
  }

  startPolling() {
    this.pollTimer = setInterval(() => this.poll(), 5000)
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  handleVisibilityChange() {
    if (document.visibilityState === "visible") {
      this.poll()
    }
  }

  async poll() {
    try {
      const response = await fetch(this.pollUrlValue, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        }
      })
      if (!response.ok) throw new Error("Failed to fetch blockers")

      const data = await response.json()
      this.updateWizard(data)
    } catch (error) {
      console.error("Error polling blockers:", error)
    }
  }

  updateWizard(data) {
    const itemsMap = { ...data.blocked_details, ...data.exceptions }
    this.itemsMap = itemsMap

    // Check if all blocking steps are fully resolved (0 items)
    const blockingKeys = this.stepsValue.filter(key => !this.warningStepsValue.includes(key))
    const totalRemainingBlockers = blockingKeys.reduce((acc, key) => {
      const count = (itemsMap[key] || []).length
      return acc + count
    }, 0)

    if (totalRemainingBlockers === 0) {
      this.showCompletion()
      return
    }

    // Otherwise, ensure wizard container is shown and completion is hidden
    this.wizardContainerTarget.classList.remove("hidden")
    this.completionContainerTarget.classList.add("hidden")

    // Update step indicator pills
    this.updateIndicators(itemsMap)

    // Render active step
    const currentStepKey = this.stepsValue[this.currentStepIndex]
    const currentItems = itemsMap[currentStepKey] || []
    const itemsCount = currentItems.length

    // Update title and description
    const info = STEP_INFO[currentStepKey] || { title: currentStepKey, description: "" }
    this.stepTitleTarget.textContent = info.title
    this.stepDescriptionTarget.textContent = info.description

    // Manage warnings UI
    const isWarning = this.warningStepsValue.includes(currentStepKey)
    if (isWarning) {
      this.warningBadgeTarget.classList.remove("hidden")
      this.skipButtonTarget.classList.remove("hidden")
    } else {
      this.warningBadgeTarget.classList.add("hidden")
      this.skipButtonTarget.classList.add("hidden")
    }

    // Update Progress Bar
    const totalSteps = this.stepsValue.length
    const progressPercent = ((this.currentStepIndex + 1) / totalSteps) * 100
    this.progressBarTarget.style.width = `${progressPercent}%`
    
    const remainingItemsText = itemsCount === 1 ? "1 item remaining" : `${itemsCount} items remaining`
    this.progressTextTarget.textContent = `Step ${this.currentStepIndex + 1} of ${totalSteps} · ${remainingItemsText}`

    // If active step is cleared
    if (itemsCount === 0) {
      this.stepTableContainerTarget.classList.add("hidden")
      
      if (isWarning) {
        // Warning step: auto-advance immediately (no countdown)
        this.advance()
      } else {
        // Blocking step: start countdown to auto-advance
        this.showCountdown()
      }
    } else {
      // Step has items: cancel countdown if active
      this.stopCountdown()
      this.countdownContainerTarget.classList.add("hidden")
      this.stepTableContainerTarget.classList.remove("hidden")
      this.renderTable(currentStepKey, currentItems)
    }
  }

  updateIndicators(itemsMap) {
    this.stepIndicatorTargets.forEach((el, index) => {
      const stepKey = el.dataset.stepKey
      const isWarning = this.warningStepsValue.includes(stepKey)
      const count = (itemsMap[stepKey] || []).length

      // Highlight active step
      const isActive = index === this.currentStepIndex
      
      // Reset classes
      el.className = "flex-1 py-3 text-center border-b-2 font-bold text-xs transition-all duration-300 "

      if (isActive) {
        if (isWarning) {
          el.className += "border-amber-500 text-amber-800 bg-amber-50/50"
        } else {
          el.className += count > 0 
            ? "border-red-500 text-red-800 bg-red-50/50" 
            : "border-emerald-500 text-emerald-800 bg-emerald-50/50"
        }
      } else {
        if (count > 0) {
          if (isWarning) {
            el.className += "border-slate-200 text-amber-600/80 hover:bg-slate-50/50"
          } else {
            el.className += "border-slate-200 text-red-600/80 hover:bg-slate-50/50"
          }
        } else {
          el.className += "border-slate-200 text-slate-400 hover:bg-slate-50/50"
        }
      }

      // Update badge text if badge element exists inside the pill
      const badge = el.querySelector(".step-count-badge")
      if (badge) {
        badge.textContent = count
        badge.className = "ml-1.5 inline-flex items-center justify-center size-5 rounded-full text-[10px] font-black "
        if (count > 0) {
          badge.className += isWarning ? "bg-amber-100 text-amber-800" : "bg-red-100 text-red-800"
        } else {
          badge.className += "bg-slate-100 text-slate-400"
        }
      }
    })
  }

  showCountdown() {
    if (this.countdownActive) return

    this.countdownActive = true
    this.countdownSeconds = 3
    this.countdownTimerTarget.textContent = this.countdownSeconds
    this.countdownContainerTarget.classList.remove("hidden")

    this.countdownInterval = setInterval(() => {
      this.countdownSeconds -= 1
      this.countdownTimerTarget.textContent = this.countdownSeconds

      if (this.countdownSeconds <= 0) {
        this.stopCountdown()
        this.advance()
      }
    }, 1000)
  }

  stopCountdown() {
    if (this.countdownInterval) {
      clearInterval(this.countdownInterval)
      this.countdownInterval = null
    }
    this.countdownActive = false
  }

  skip(event) {
    if (event) event.preventDefault()
    this.advance()
  }

  goToStep(event) {
    if (event) event.preventDefault()
    const index = parseInt(event.currentTarget.dataset.index, 10)
    if (!isNaN(index) && index >= 0 && index < this.stepsValue.length) {
      this.stopCountdown()
      this.currentStepIndex = index
      this.poll()
    }
  }

  advance() {
    this.stopCountdown()
    if (this.currentStepIndex < this.stepsValue.length - 1) {
      this.currentStepIndex += 1
      this.poll()
    } else {
      // Reached the end of wizard steps
      this.showCompletion()
    }
  }

  showCompletion() {
    this.stopCountdown()
    this.wizardContainerTarget.classList.add("hidden")
    this.completionContainerTarget.classList.remove("hidden")
  }

  renderTable(stepKey, items) {
    this.stepTableBodyTarget.innerHTML = ""
    
    if (!items || items.length === 0) {
      return
    }

    // Set headers based on step
    let headers = ""
    if (stepKey.startsWith("open_housekeeping") || stepKey.startsWith("open_complaint")) {
      headers = `
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Guest</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Confirmation</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Details</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Status</th>
        <th class="px-6 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wider">Action</th>
      `
    } else if (stepKey === "captured_payment_not_synced" || stepKey === "refund_not_synced") {
      headers = `
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Guest</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Confirmation</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Amount</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Issue</th>
        <th class="px-6 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wider">Action</th>
      `
    } else if (stepKey === "folio_balance_exceptions") {
      headers = `
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Guest</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Confirmation</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Balance</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Reason</th>
        <th class="px-6 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wider">Action</th>
      `
    } else {
      // default bookings
      headers = `
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Guest</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Confirmation</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Stay Dates</th>
        <th class="px-6 py-3 text-left text-xs font-semibold text-slate-500 uppercase tracking-wider">Issue</th>
        <th class="px-6 py-3 text-right text-xs font-semibold text-slate-500 uppercase tracking-wider">Action</th>
      `
    }
    this.stepTableHeaderTarget.innerHTML = `<tr>${headers}</tr>`

    items.forEach(item => {
      const row = document.createElement("tr")
      row.className = "border-t border-slate-100 hover:bg-slate-50/50 transition-colors"

      let cols = ""
      let actionBtn = ""
      const hotelId = this.hotelIdValue

      if (stepKey.startsWith("open_housekeeping") || stepKey.startsWith("open_complaint")) {
        const details = item.details || item.reason || ""
        const status = item.status || ""
        actionBtn = `<a href="/hotel/${hotelId}/bookings/${item.booking_id}?tab=requests" target="_blank" class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:border-slate-300 hover:bg-slate-50 transition">View Request &rarr;</a>`
        cols = `
          <td class="px-6 py-4 text-sm font-semibold text-slate-900">${item.guest_name}</td>
          <td class="px-6 py-4 text-sm text-slate-600 font-mono">${item.confirmation_token}</td>
          <td class="px-6 py-4 text-sm text-slate-600">${details}</td>
          <td class="px-6 py-4 text-sm"><span class="inline-flex items-center rounded-full bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-800 border border-amber-100">${status.toUpperCase()}</span></td>
        `
      } else if (stepKey === "captured_payment_not_synced" || stepKey === "refund_not_synced") {
        const formattedAmount = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(item.amount)
        actionBtn = `<a href="/hotel/${hotelId}/bookings/${item.booking_id}/folio" target="_blank" class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:border-slate-300 hover:bg-slate-50 transition">Go to Folio &rarr;</a>`
        cols = `
          <td class="px-6 py-4 text-sm font-semibold text-slate-900">${item.guest_name}</td>
          <td class="px-6 py-4 text-sm text-slate-600 font-mono">${item.confirmation_token}</td>
          <td class="px-6 py-4 text-sm font-bold text-slate-900">${formattedAmount}</td>
          <td class="px-6 py-4 text-sm text-red-600 font-medium">${item.reason}</td>
        `
      } else if (stepKey === "folio_balance_exceptions") {
        const formattedBalance = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(item.balance)
        const isCredit = item.balance < 0
        const balClass = isCredit ? "text-emerald-600 font-semibold" : "text-amber-600 font-semibold"
        actionBtn = `<a href="/hotel/${hotelId}/bookings/${item.booking_id}/folio" target="_blank" class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:border-slate-300 hover:bg-slate-50 transition">Go to Folio &rarr;</a>`
        cols = `
          <td class="px-6 py-4 text-sm font-semibold text-slate-900">${item.guest_name}</td>
          <td class="px-6 py-4 text-sm text-slate-600 font-mono">${item.confirmation_token}</td>
          <td class="px-6 py-4 text-sm ${balClass}">${formattedBalance}</td>
          <td class="px-6 py-4 text-sm text-slate-600">${item.reason}</td>
        `
      } else {
        // default bookings
        const dates = `${item.check_in} &ndash; ${item.check_out}`
        const isFolioAction = ["missing_nightly_charges", "outstanding_folio_balance"].includes(stepKey)
        const destUrl = isFolioAction ? `/hotel/${hotelId}/bookings/${item.booking_id}/folio` : `/hotel/${hotelId}/bookings/${item.booking_id}`
        const btnText = isFolioAction ? "Go to Folio &rarr;" : "Go to Booking &rarr;"
        actionBtn = `<a href="${destUrl}" target="_blank" class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-sm hover:border-slate-300 hover:bg-slate-50 transition">${btnText}</a>`
        cols = `
          <td class="px-6 py-4 text-sm font-semibold text-slate-900">${item.guest_name}</td>
          <td class="px-6 py-4 text-sm text-slate-600 font-mono">${item.confirmation_token}</td>
          <td class="px-6 py-4 text-sm text-slate-600">${dates}</td>
          <td class="px-6 py-4 text-sm text-red-600 font-medium">${item.reason}</td>
        `
      }

      row.innerHTML = `
        ${cols}
        <td class="px-6 py-4 text-sm text-right whitespace-nowrap">${actionBtn}</td>
      `
      this.stepTableBodyTarget.appendChild(row)
    })
  }
}
