import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modeCheckbox", "rangeFields", "customFields", "start", "customList", "preview", "quantity", "inputContainer", "hint"]
  static values = {
    defaultStart: { type: Number, default: 101 },
    reservedNumbers: { type: Array, default: [] }
  }

  connect() {
    // ... initial guess logic ...
    if (this.customListTarget.value.trim() !== "") {
      const match = this.customListTarget.value.match(/\d+/)
      if (match && !this.startTarget.value) {
        this.startTarget.value = match[0]
      }
    }

    // The mode switch now submits room_number_mode itself, so the previous mode
    // is tracked here rather than read back off a hidden companion field.
    // Seeding it from the switch keeps connect() a no-op transition, the way
    // reading the persisted hidden value used to be.
    this.mode = this.modeCheckboxTarget.checked ? "custom" : "range"
    this.toggleMode()
  }

  toggleMode() {
    const isCustom = this.modeCheckboxTarget.checked
    const previousMode = this.mode
    this.mode = isCustom ? "custom" : "range"

    if (isCustom) {
      this.rangeFieldsTarget.classList.add("hidden")
      this.customFieldsTarget.classList.remove("hidden")

      if (previousMode === "range" && !this.customListTarget.value.trim()) {
        const quantity = parseInt(this.quantityTarget.value) || 0
        const start = parseInt(this.startTarget.value) || this.defaultStartValue
        let numbers = []
        for (let i = 0; i < quantity; i++) {
          numbers.push(`${start + i}`)
        }
        this.customListTarget.value = numbers.join(", ")
      }
    } else {
      this.rangeFieldsTarget.classList.remove("hidden")
      this.customFieldsTarget.classList.add("hidden")
      if (!this.startTarget.value) {
        this.startTarget.value = this.defaultStartValue.toString()
      }
    }
    this.generate()
  }

  generate() {
    const isCustom = this.modeCheckboxTarget.checked
    const quantity = parseInt(this.quantityTarget.value) || 0
    let numbers = []

    if (quantity > 0) {
      if (isCustom) {
        const customVal = this.customListTarget.value
        numbers = customVal.split(",").map(n => n.trim()).filter(n => n !== "")

        if (numbers.length > 0) {
          const match = numbers[0].match(/\d+/)
          if (match) {
            this.startTarget.value = match[0]
          }
        }
      } else {
        let start = parseInt(this.startTarget.value) || this.defaultStartValue
        for (let i = 0; i < quantity; i++) {
          numbers.push(`${start + i}`)
        }
      }
    }

    this.updateInputs(numbers)
  }

  updateInputs(numbers) {
    this.inputContainerTarget.replaceChildren()
    numbers.forEach(number => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "room_type[room_numbers][]"
      input.value = number
      this.inputContainerTarget.appendChild(input)
    })

    const quantity = parseInt(this.quantityTarget.value) || 0

    // Room numbers are free text in custom mode, so they are written as text
    // nodes rather than interpolated into markup.
    this.previewTarget.replaceChildren()
    if (numbers.length === 0) {
      const empty = document.createElement("span")
      empty.className = "text-sm text-muted-foreground"
      empty.textContent = "No room numbers generated"
      this.previewTarget.appendChild(empty)
    } else {
      numbers.forEach(number => {
        const chip = document.createElement("span")
        chip.className = "inline-flex items-center gap-x-1.5 rounded-md border border-border bg-muted px-2 py-1 text-xs font-semibold text-foreground"
        chip.textContent = number
        this.previewTarget.appendChild(chip)
      })
    }

    this.updateHint(numbers, quantity)
  }

  updateHint(numbers, quantity) {
    if (!this.hasHintTarget) return

    const messages = []
    if (numbers.length !== quantity && quantity > 0) {
      messages.push(`The number of rooms (${numbers.length}) does not match the total number of rooms (${quantity}).`)
    }

    const reserved = new Set(this.reservedNumbersValue)
    const conflicts = [...new Set(numbers.filter(number => reserved.has(number)))]
    if (conflicts.length > 0) {
      messages.push(`These room numbers already belong to another room category: ${conflicts.join(", ")}.`)
    }

    this.hintTarget.textContent = messages.join(" ")
    this.hintTarget.classList.toggle("hidden", messages.length === 0)
  }
}
