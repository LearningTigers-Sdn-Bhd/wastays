import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["mode", "rangeFields", "customFields", "start", "customList", "preview", "quantity", "inputContainer"]

  connect() {
    if (this.customListTarget.value && !this.startTarget.value) {
      this.modeTarget.value = "custom"
    }
    this.toggleMode()
  }

  toggleMode() {
    const mode = this.modeTarget.value
    if (mode === "range") {
      this.rangeFieldsTarget.classList.remove("hidden")
      this.customFieldsTarget.classList.add("hidden")
    } else {
      this.rangeFieldsTarget.classList.add("hidden")
      this.customFieldsTarget.classList.remove("hidden")
    }
    this.generate()
  }

  generate() {
    const mode = this.modeTarget.value
    let numbers = []
    const quantity = parseInt(this.quantityTarget.value) || 0

    if (quantity <= 0) {
      this.updateInputs([])
      return
    }

    if (mode === "range") {
      const start = parseInt(this.startTarget.value)

      if (!isNaN(start)) {
        for (let i = 0; i < quantity; i++) {
          numbers.push(`${start + i}`)
        }
      }
    } else {
      const customVal = this.customListTarget.value
      numbers = customVal.split(",").map(n => n.trim()).filter(n => n !== "")
      // Limit to quantity? Or maybe update quantity?
      // Let's just use what they typed but highlight if count doesn't match
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

    // Validation hint
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
