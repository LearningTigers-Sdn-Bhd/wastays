import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["roomCard", "quantityDisplay", "stickyBar", "summaryText", "totalPriceText", "formInputs", "validationWarning", "submitButton"]
  static values = {
    adults: Number,
    children: Number,
    currency: String
  }

  connect() {
    this.selections = {} // Format: { roomTypeId: quantity }
    this.roomData = {} // Format: { roomTypeId: { price, name, maxCapacity, availableQty } }

    this.initializeRoomData()
    this.updateUI()
  }

  initializeRoomData() {
    this.roomCardTargets.forEach(card => {
      const id = card.dataset.roomTypeId
      const price = parseFloat(card.dataset.roomPrice || 0)
      const name = card.dataset.roomName
      const maxCapacity = parseInt(card.dataset.roomMaxCapacity || 1)
      const availableQty = parseInt(card.dataset.roomAvailableQuantity || 0)

      this.roomData[id] = { price, name, maxCapacity, availableQty }
      this.selections[id] = 0
    })
  }

  add(event) {
    const id = event.currentTarget.dataset.roomTypeId
    const data = this.roomData[id]

    if (data && data.availableQty > 0) {
      this.selections[id] = 1
      this.updateUI()
    }
  }

  increment(event) {
    const id = event.currentTarget.dataset.roomTypeId
    const data = this.roomData[id]

    if (data && this.selections[id] < data.availableQty) {
      this.selections[id] += 1
      this.updateUI()
    }
  }

  decrement(event) {
    const id = event.currentTarget.dataset.roomTypeId
    if (this.selections[id] > 0) {
      this.selections[id] -= 1
      this.updateUI()
    }
  }

  updateUI() {
    let totalRooms = 0
    let totalPrice = 0
    let totalCapacity = 0
    const summaryItems = []

    // 1. Update Room Card Steppers
    this.roomCardTargets.forEach(card => {
      const id = card.dataset.roomTypeId
      const qty = this.selections[id] || 0
      const availableQty = this.roomData[id]?.availableQty || 0

      // Toggle visibility of Add button vs Stepper control
      const addButton = card.querySelector('[data-role="add-button"]')
      const stepper = card.querySelector('[data-role="stepper"]')
      const cardContainer = card.querySelector('[data-role="card-container"]')

      if (addButton && stepper) {
        if (qty > 0) {
          addButton.classList.add("hidden")
          stepper.classList.remove("hidden")
          if (cardContainer) {
            cardContainer.classList.add("border-brand-primary", "bg-brand-primary/5")
          }
        } else {
          addButton.classList.remove("hidden")
          stepper.classList.add("hidden")
          if (cardContainer) {
            cardContainer.classList.remove("border-brand-primary", "bg-brand-primary/5")
          }
        }
      }

      // Update quantity display
      const display = card.querySelector(`[data-room-selector-target="quantityDisplay"]`)
      if (display) {
        display.textContent = qty
      }

      // Disable/Enable stepper buttons
      const decBtn = card.querySelector('[data-role="decrement-btn"]')
      const incBtn = card.querySelector('[data-role="increment-btn"]')
      if (decBtn) decBtn.disabled = (qty <= 0)
      if (incBtn) incBtn.disabled = (qty >= availableQty)

      // Accumulate
      if (qty > 0) {
        const roomInfo = this.roomData[id]
        totalRooms += qty
        totalPrice += roomInfo.price * qty
        totalCapacity += roomInfo.maxCapacity * qty
        summaryItems.push(`${qty}x ${roomInfo.name}`)
      }
    })

    // 2. Update Sticky Bar
    if (totalRooms > 0) {
      this.stickyBarTarget.classList.remove("translate-y-full", "opacity-0")
      this.stickyBarTarget.classList.add("translate-y-0", "opacity-100")
      this.summaryTextTarget.textContent = summaryItems.join(", ")

      // Format Price
      const formattedPrice = new Intl.NumberFormat(undefined, {
        style: 'currency',
        currency: this.currencyValue || 'MYR',
        minimumFractionDigits: 2
      }).format(totalPrice)

      this.totalPriceTextTarget.textContent = formattedPrice

      // 3. Validation Rules
      const totalGuestsNeeded = this.adultsValue + this.childrenValue
      let warningMsg = ""

      if (totalCapacity < totalGuestsNeeded) {
        warningMsg = `Selected rooms capacity (${totalCapacity} guests) is less than your search party (${totalGuestsNeeded} guests).`
      } else if (totalRooms > this.adultsValue) {
        warningMsg = `You selected ${totalRooms} rooms but only entered ${this.adultsValue} adults. (Each room needs at least 1 adult).`
      }

      if (warningMsg) {
        this.validationWarningTarget.textContent = warningMsg
        this.validationWarningTarget.classList.remove("hidden")
        this.submitButtonTarget.disabled = true
      } else {
        this.validationWarningTarget.classList.add("hidden")
        this.submitButtonTarget.disabled = false
      }

      // 4. Update Form Hidden Inputs
      this.updateHiddenInputs()
    } else {
      this.stickyBarTarget.classList.add("translate-y-full", "opacity-0")
      this.stickyBarTarget.classList.remove("translate-y-0", "opacity-100")
    }
  }

  updateHiddenInputs() {
    this.formInputsTarget.innerHTML = ""

    Object.entries(this.selections).forEach(([id, qty]) => {
      if (qty > 0) {
        const typeInput = document.createElement("input")
        typeInput.type = "hidden"
        typeInput.name = "allocations[][room_type_id]"
        typeInput.value = id
        this.formInputsTarget.appendChild(typeInput)

        const qtyInput = document.createElement("input")
        qtyInput.type = "hidden"
        qtyInput.name = "allocations[][quantity]"
        qtyInput.value = qty
        this.formInputsTarget.appendChild(qtyInput)
      }
    })
  }
}
