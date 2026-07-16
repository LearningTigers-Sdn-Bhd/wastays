import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  show(event) {
    const template = document.getElementById(event.currentTarget.dataset.bannerTemplateId)
    if (!template) return

    document.getElementById(template.dataset.bannerId)?.remove()
    document.body.append(template.content.cloneNode(true))
  }
}
