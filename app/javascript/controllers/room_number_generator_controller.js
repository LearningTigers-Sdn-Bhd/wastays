import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modeCheckbox", "modeInput", "rangeFields", "customFields", "start", "customList", "preview", "quantity", "inputContainer"]

  connect() {
    // If we have existing room numbers, try to guess the starting number for range mode
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
    this.modeInputTarget.value = isCustom ? "custom" : "range"

    if (isCustom) {
      this.rangeFieldsTarget.classList.add("hidden")
      this.customFieldsTarget.classList.remove("hidden")
    } else {
      this.rangeFieldsTarget.classList.remove("hidden")
      this.customFieldsTarget.classList.add("hidden")
      if (!this.startTarget.value) {
        this.startTarget.value = "101"
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

        // REVERSE SYNC: If they type a first number in custom, update the range start
        if (numbers.length > 0) {
          const match = numbers[0].match(/\d+/)
          if (match) {
            this.startTarget.value = match[0]
          }
        }
      } else {
        let start = parseInt(this.startTarget.value) || 101
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

    const hint = document.getElementById("room-numbers-hint")
    if (hint) {
      if (numbers.length !== quantity && quantity > 0) {
        hint.innerHTML = `Warning: Number of rooms (${numbers.length}) does not match Total Quantity (${quantity})`
        hint.classList.remove("hidden")
        hint.classList.add("text-red-500")
      } else {
        hint.classList.add("hidden")
      }
    }
  }
}
