import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modeCheckbox", "modeInput", "rangeFields", "customFields", "start", "customList", "preview", "quantity", "inputContainer", "hint"]
  static values = { defaultStart: { type: Number, default: 101 } }

  connect() {
    // ... initial guess logic ...
    if (this.customListTarget.value.trim() !== "") {
      const match = this.customListTarget.value.match(/\d+/)
      if (match && !this.startTarget.value) {
        this.startTarget.value = match[0]
      }
    }

    this.toggleMode()
  }

  toggleMode() {
    const isCustom = this.modeCheckboxTarget.checked
    const previousMode = this.modeInputTarget.value
    this.modeInputTarget.value = isCustom ? "custom" : "range"

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
    this.inputContainerTarget.innerHTML = ""
    numbers.forEach(number => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "room_type[room_numbers][]"
      input.value = number
      this.inputContainerTarget.appendChild(input)
    })

    const quantity = parseInt(this.quantityTarget.value) || 0
    let previewHtml = numbers.map(n =>
      `<span class="inline-flex items-center gap-x-1.5 py-1 px-2 rounded-lg text-xs font-semibold bg-slate-100 text-slate-700 border border-slate-200">${n}</span>`
    ).join(" ")

    if (numbers.length === 0) {
      previewHtml = `<span class="text-slate-400 italic text-sm">No room numbers generated</span>`
    }

    this.previewTarget.innerHTML = previewHtml

    if (this.hasHintTarget) {
      if (numbers.length !== quantity && quantity > 0) {
        this.hintTarget.innerHTML = `Warning: Number of rooms (${numbers.length}) does not match Total Quantity (${quantity})`
        this.hintTarget.classList.remove("hidden")
        this.hintTarget.classList.add("text-red-500")
      } else {
        this.hintTarget.classList.add("hidden")
      }
    }
  }
}
