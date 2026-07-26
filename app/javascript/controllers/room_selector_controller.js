import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["roomCard", "quantityDisplay", "stickyBar", "summaryText", "totalPriceText", "formInputs", "validationWarning", "submitButton"]
  static values = {
    adults: Number,
    children: Number,
    currency: String,
    paxPricingOnly: Boolean,
    childAges: Array
  }

  connect() {
    this.selections = {} // Format: { roomTypeId: quantity }
    this.roomData = {} // Format: { roomTypeId: { price, paxPrice, name, maxCapacity, availableQty, singleSupplement, childMultiplier } }

    this.initializeRoomData()
    this.updateUI()
  }

  disconnect() {
    document.documentElement.classList.remove("sticky-bar-active")
  }

  initializeRoomData() {
    this.roomCardTargets.forEach(card => {
      const id = card.dataset.roomTypeId
      const price = parseFloat(card.dataset.roomPrice || 0)
      const paxPrice = parseFloat(card.dataset.roomPaxPrice || 0)
      const name = card.dataset.roomName
      const maxCapacity = parseInt(card.dataset.roomMaxCapacity || 1)
      const maxAdults = parseInt(card.dataset.roomMaxAdults || maxCapacity)
      const maxChildren = parseInt(card.dataset.roomMaxChildren || 0)
      const availableQty = parseInt(card.dataset.roomAvailableQuantity || 0)

      const singleSupplement = parseFloat(card.dataset.roomSingleSupplement || 0)
      const childMultiplier = parseFloat(card.dataset.roomChildMultiplier || 1)
      let ageBands = []
      try {
        ageBands = JSON.parse(card.dataset.roomAgeBands || "[]")
      } catch (e) {
        ageBands = []
      }

      this.roomData[id] = {
        price,
        paxPrice,
        name,
        maxCapacity,
        maxAdults,
        maxChildren,
        availableQty,
        singleSupplement,
        childMultiplier,
        ageBands
      }
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

  distributeGuests(adults, children, selectedRooms, childAges = []) {
    const sortedRooms = [...selectedRooms].sort((a, b) => b.maxCapacity - a.maxCapacity)
    const numRooms = sortedRooms.length
    if (adults < numRooms) return null

    const agesPool = childAges.length === children ? [...childAges] : []

    const occupancies = Array.from({ length: numRooms }, (_, i) => ({
      room: sortedRooms[i],
      adults: 1,
      children: 0,
      childAges: []
    }))

    let tempAdults = adults - numRooms
    let tempChildren = children

    const guestPool = [
      { key: 'adults', count: tempAdults },
      { key: 'children', count: tempChildren }
    ]

    for (const pool of guestPool) {
      let count = pool.count
      if (count <= 0) continue

      for (let i = 0; i < numRooms; i++) {
        const room = occupancies[i].room
        const currentTotal = occupancies[i].adults + occupancies[i].children
        let spaceLeft = room.maxCapacity - currentTotal

        let specificLimit
        let currentSpecific

        if (pool.key === 'adults') {
          specificLimit = room.maxAdults
          currentSpecific = occupancies[i].adults
        } else {
          specificLimit = room.maxChildren
          currentSpecific = occupancies[i].children
        }

        const specificSpace = Math.max(specificLimit - currentSpecific, 0)
        spaceLeft = Math.min(spaceLeft, specificSpace)
        if (spaceLeft <= 0) continue

        const toAdd = Math.min(spaceLeft, count)
        occupancies[i][pool.key] += toAdd
        if (pool.key === 'children' && agesPool.length > 0) {
          occupancies[i].childAges.push(...agesPool.splice(0, toAdd))
        }
        count -= toAdd
        if (count <= 0) break
      }

      if (count > 0) return null
    }

    return occupancies
  }

  perChildPrice(paxPrice, ageBands, flatMultiplier, age) {
    const band = ageBands.find((b) => age >= b.minAge && age <= b.maxAge)
    if (band) {
      return band.pricingMode === "amount" ? band.value : paxPrice * band.value
    }
    return paxPrice * flatMultiplier
  }

  updateUI() {
    let totalRooms = 0
    let totalPrice = 0
    let totalCapacity = 0
    const summaryItems = []
    const selectedRoomsList = []

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
        totalCapacity += roomInfo.maxCapacity * qty
        summaryItems.push(`${qty}x ${roomInfo.name}`)

        for (let k = 0; k < qty; k++) {
          selectedRoomsList.push({ id, ...roomInfo })
        }
      }
    })

    // Distribute guests across the selected rooms, respecting each room's own
    // max_adults/max_children caps (not just its total capacity) — used both
    // for pax pricing and to validate the combo can legally hold this party.
    let occupancies = null
    if (totalRooms > 0) {
      occupancies = this.distributeGuests(
        this.adultsValue,
        this.childrenValue,
        selectedRoomsList,
        this.hasChildAgesValue ? this.childAgesValue : []
      )
    }

    // Calculate Price based on Mode
    if (totalRooms > 0) {
      if (this.paxPricingOnlyValue) {
        if (occupancies) {
          occupancies.forEach(occ => {
            const room = occ.room
            const roomPax = occ.adults + occ.children

            let roomPrice = occ.adults * room.paxPrice
            if (occ.childAges.length === occ.children && occ.childAges.length > 0) {
              roomPrice += occ.childAges.reduce((sum, age) => sum + this.perChildPrice(room.paxPrice, room.ageBands, room.childMultiplier, age), 0)
            } else {
              roomPrice += occ.children * room.paxPrice * room.childMultiplier
            }

            if (roomPax === 1) {
              roomPrice += room.singleSupplement
            }

            totalPrice += roomPrice
          })
        } else {
          totalPrice = 0
        }
      } else {
        selectedRoomsList.forEach(room => {
          totalPrice += room.price
        })
      }
    }

    // 2. Update Sticky Bar
    if (totalRooms > 0) {
      this.stickyBarTarget.classList.remove("translate-y-full", "opacity-0")
      this.stickyBarTarget.classList.add("translate-y-0", "opacity-100")
      document.documentElement.classList.add("sticky-bar-active")
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
      } else if (!occupancies) {
        warningMsg = `These rooms can't fit ${this.adultsValue} adults and ${this.childrenValue} children — one or more room types have a lower adult/child limit per room. Add another room or pick a bigger room type.`
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
      document.documentElement.classList.remove("sticky-bar-active")
    }
  }

  updateHiddenInputs() {
    this.formInputsTarget.innerHTML = ""
    let index = 0

    Object.entries(this.selections).forEach(([id, qty]) => {
      if (qty > 0) {
        const typeInput = document.createElement("input")
        typeInput.type = "hidden"
        typeInput.name = `allocations[${index}][room_type_id]`
        typeInput.value = id
        this.formInputsTarget.appendChild(typeInput)

        const qtyInput = document.createElement("input")
        qtyInput.type = "hidden"
        qtyInput.name = `allocations[${index}][quantity]`
        qtyInput.value = qty
        this.formInputsTarget.appendChild(qtyInput)

        index++
      }
    })
  }
}
