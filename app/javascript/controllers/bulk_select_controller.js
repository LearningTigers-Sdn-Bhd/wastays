import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "checkbox", "selectAll", "banner", "count", "idsInput" ]

  connect() {
    this.update()
  }

  toggleAll(event) {
    const checked = event.target.checked
    this.checkboxTargets.forEach(checkbox => {
      checkbox.checked = checked
    })
    this.update()
  }

  toggleSingle(event) {
    const targetCheckbox = event.target
    const guestId = targetCheckbox.value
    const isChecked = targetCheckbox.checked

    // Sync state between desktop and mobile checkboxes for the same guest
    this.checkboxTargets.forEach(cb => {
      if (cb.value === guestId) {
        cb.checked = isChecked
      }
    })

    // Update master selectAll checkbox state based on desktop checkbox values
    const desktopCheckboxes = this.checkboxTargets.filter(cb => !cb.closest('.lg:hidden'))
    const allChecked = desktopCheckboxes.length > 0 && desktopCheckboxes.every(cb => cb.checked)
    const noneChecked = desktopCheckboxes.every(cb => !cb.checked)
    
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = allChecked
      this.selectAllTarget.indeterminate = !allChecked && !noneChecked
    }
    
    this.update()
  }

  update() {
    const checkedCheckboxes = this.checkboxTargets.filter(cb => cb.checked)
    const uniqueIds = [...new Set(checkedCheckboxes.map(cb => cb.value))]
    const selectedCount = uniqueIds.length

    if (selectedCount > 0) {
      if (this.hasBannerTarget) {
        this.bannerTarget.classList.remove("hidden")
        this.bannerTarget.classList.add("flex")
      }
      
      if (this.hasCountTarget) {
        this.countTarget.textContent = `${selectedCount} ${selectedCount === 1 ? 'guest' : 'guests'} selected`
      }

      if (this.hasIdsInputTarget) {
        this.idsInputTarget.value = JSON.stringify(uniqueIds)
      }
    } else {
      if (this.hasBannerTarget) {
        this.bannerTarget.classList.add("hidden")
        this.bannerTarget.classList.remove("flex")
      }
      
      if (this.hasIdsInputTarget) {
        this.idsInputTarget.value = ""
      }
      
      if (this.hasSelectAllTarget) {
        this.selectAllTarget.checked = false
        this.selectAllTarget.indeterminate = false
      }
    }
  }

  clear() {
    this.checkboxTargets.forEach(cb => cb.checked = false)
    if (this.hasSelectAllTarget) {
      this.selectAllTarget.checked = false
      this.selectAllTarget.indeterminate = false
    }
    this.update()
  }
}
