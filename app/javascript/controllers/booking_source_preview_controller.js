import { Controller } from "@hotwired/stimulus"

// Live preview for the superadmin "Booking Source" form: keeps the fallback
// initial badge in sync with the color/initial inputs, previews the fallback
// icon as it's typed, toggles the "remove current logo" preview, and
// shows/hides the OTA-only fallback badge section as the category changes.
// New logo uploads get their own preview from PanelsUI::Dropzone.
export default class extends Controller {
  static targets = [
    "logoPreview", "logoPlaceholder", "removeLogoCheckbox",
    "colorInput", "textColorInput", "initialInput", "badgePreview",
    "iconInput", "iconPreview", "otaOnlySection"
  ]
  static values = { iconPreviewUrl: String }

  connect() {
    this.toggleKindFields()
  }

  // PanelsUI::SelectMenu progressively enhances the native <select> without
  // exposing it as a Stimulus target, so it's queried directly by form field
  // name instead — this element is also what dispatches the bubbling `change`
  // that the select's data-action on this controller listens for.
  get kindSelect() {
    return this.element.querySelector('select[name="booking_source[kind]"]')
  }

  toggleKindFields() {
    const isOta = this.kindSelect?.value === "ota"
    this.otaOnlySectionTargets.forEach((section) => section.classList.toggle("hidden", !isOta))
  }

  toggleRemoveLogo(event) {
    if (!event.target.checked) return

    this.logoPreviewTarget.classList.add("hidden")
    if (this.hasLogoPlaceholderTarget) this.logoPlaceholderTarget.classList.remove("hidden")
  }

  updateBadge() {
    if (!this.hasBadgePreviewTarget) return

    if (this.hasColorInputTarget) this.badgePreviewTarget.style.backgroundColor = this.colorInputTarget.value
    if (this.hasTextColorInputTarget) this.badgePreviewTarget.style.color = this.textColorInputTarget.value
    if (this.hasInitialInputTarget) this.badgePreviewTarget.textContent = this.initialInputTarget.value.slice(0, 2)
  }

  previewIcon() {
    if (!this.hasIconPreviewTarget || !this.hasIconPreviewUrlValue) return

    clearTimeout(this.iconPreviewTimeout)
    this.iconPreviewTimeout = setTimeout(() => this.fetchIconPreview(this.iconInputTarget.value.trim()), 200)
  }

  async fetchIconPreview(name) {
    const url = new URL(this.iconPreviewUrlValue, window.location.origin)
    url.searchParams.set("name", name)

    const response = await fetch(url, { headers: { "Accept": "text/html" } })
    if (response.ok) this.iconPreviewTarget.innerHTML = await response.text()
  }
}
