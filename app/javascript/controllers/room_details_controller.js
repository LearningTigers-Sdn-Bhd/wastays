import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "mainImage", "backdropImage", "thumbnails", "name", "description", "adults", "children", "childrenContainer", "indexDisplay", "totalCount", "amenitiesSection", "amenitiesList", "hotelAmenitiesSection", "hotelAmenitiesList", "roomAmenitiesToggle", "hotelAmenitiesToggle"]
  static values = {
    photos: Array,
    index: Number
  }

  open(event) {
    event.preventDefault()
    const data = JSON.parse(event.currentTarget.dataset.roomDetails)
    
    this.nameTarget.textContent = data.name
    this.descriptionTarget.textContent = data.description
    this.adultsTarget.textContent = `${data.max_adults} Adults`
    
    if (data.max_children > 0) {
      this.childrenTarget.textContent = `${data.max_children} Children`
      if (this.hasChildrenContainerTarget) this.childrenContainerTarget.classList.remove("hidden")
    } else {
      if (this.hasChildrenContainerTarget) this.childrenContainerTarget.classList.add("hidden")
    }

    // Room Amenities setup
    const roomAmenities = data.room_amenities || data.amenities || []
    if (roomAmenities.length > 0) {
      this.renderAmenities(roomAmenities, this.amenitiesListTarget, this.roomAmenitiesToggleTarget)
      this.amenitiesSectionTarget.classList.remove("hidden")
    } else {
      this.amenitiesSectionTarget.classList.add("hidden")
    }

    // Hotel Amenities setup
    if (data.hotel_amenities && data.hotel_amenities.length > 0) {
      this.renderAmenities(data.hotel_amenities, this.hotelAmenitiesListTarget, this.hotelAmenitiesToggleTarget)
      this.hotelAmenitiesSectionTarget.classList.remove("hidden")
    } else {
      if (this.hasHotelAmenitiesSectionTarget) this.hotelAmenitiesSectionTarget.classList.add("hidden")
    }
    
    // Photos setup
    this.photosValue = data.photos || []
    this.indexValue = 0
    this.touchStartX = null
    this.touchCurrentX = null

    if (this.hasTotalCountTarget) this.totalCountTarget.textContent = this.photosValue.length || 1
    
    this.renderThumbnails()
    this.showImage()

    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  next(event) {
    if (event) event.preventDefault()
    if (this.photosValue.length === 0) return
    this.indexValue = (this.indexValue + 1) % this.photosValue.length
    this.showImage()
  }

  prev(event) {
    if (event) event.preventDefault()
    if (this.photosValue.length === 0) return
    this.indexValue = (this.indexValue - 1 + this.photosValue.length) % this.photosValue.length
    this.showImage()
  }

  switchImage(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.indexValue = index
    this.showImage()
  }

  showImage() {
    if (this.photosValue.length > 0) {
      const currentPhoto = this.photosValue[this.indexValue]
      this.mainImageTarget.src = currentPhoto
      if (this.hasBackdropImageTarget) this.backdropImageTarget.src = currentPhoto
      if (this.hasIndexDisplayTarget) this.indexDisplayTarget.textContent = this.indexValue + 1
      this.mainImageTarget.classList.remove("hidden")
      if (this.hasBackdropImageTarget) this.backdropImageTarget.classList.remove("hidden")
      
      // Update thumbnail borders
      this.thumbnailsTarget.querySelectorAll("img").forEach((img, idx) => {
        if (idx === this.indexValue) {
          img.classList.remove("border-transparent")
          img.classList.add("border-blue-600")
        } else {
          img.classList.remove("border-blue-600")
          img.classList.add("border-transparent")
        }
      })
    } else {
      this.mainImageTarget.classList.add("hidden")
      if (this.hasBackdropImageTarget) this.backdropImageTarget.classList.add("hidden")
    }
  }

  renderThumbnails() {
    this.thumbnailsTarget.innerHTML = ""
    this.photosValue.forEach((photo, index) => {
      const thumb = document.createElement("img")
      thumb.src = photo
      thumb.className = "h-28 w-32 shrink-0 rounded-xl object-cover cursor-pointer border-2 transition-colors border-transparent hover:border-blue-300"
      thumb.dataset.action = "click->room-details#switchImage"
      thumb.dataset.index = index
      this.thumbnailsTarget.appendChild(thumb)
    })
  }

  renderAmenities(amenities, listTarget, toggleTarget) {
    listTarget.innerHTML = ""
    const template = document.getElementById("amenity-item-template")
    const limit = 9
    const hasMore = amenities.length > limit

    amenities.forEach((amenity, index) => {
      const clone = document.importNode(template.content, true)
      const container = clone.firstElementChild
      
      container.querySelector("[data-amenity-name]").textContent = amenity.name
      
      const iconContainer = container.querySelector("[data-amenity-icon-container]")
      const iconSource = document.getElementById(`icon-${amenity.icon}`)
      
      if (iconSource) {
        iconContainer.innerHTML = iconSource.innerHTML
      }

      if (index >= limit) {
        container.classList.add("hidden", "extra-amenity-item")
      }

      listTarget.appendChild(container)
    })

    if (hasMore && toggleTarget) {
      toggleTarget.classList.remove("hidden")
      this.setToggleLabel(toggleTarget, true, amenities.length)
      // Reset rotation
      const svg = toggleTarget.querySelector("svg")
      if (svg) svg.classList.remove("rotate-180")
    } else if (toggleTarget) {
      toggleTarget.classList.add("hidden")
    }
  }

  toggleRoomAmenities(event) {
    this.toggleAmenities(this.amenitiesListTarget, this.roomAmenitiesToggleTarget)
  }

  toggleHotelAmenities(event) {
    this.toggleAmenities(this.hotelAmenitiesListTarget, this.hotelAmenitiesToggleTarget)
  }

  toggleAmenities(listTarget, toggleTarget) {
    const extras = listTarget.querySelectorAll(".extra-amenity-item")
    if (extras.length === 0) return

    const isShowingMore = extras[0].classList.contains("hidden")
    const totalCount = listTarget.children.length

    extras.forEach(el => el.classList.toggle("hidden"))
    this.setToggleLabel(toggleTarget, !isShowingMore, totalCount)
    
    // Toggle SVG rotation
    const svg = toggleTarget.querySelector("svg")
    if (svg) svg.classList.toggle("rotate-180")
  }

  setToggleLabel(button, isCollapsed, count) {
    const span = button.querySelector("span")
    if (span) {
      span.textContent = isCollapsed ? "Show more" : "Show less"
    }
  }

  touchStart(event) {
    if (window.innerWidth >= 768) return
    if (!event.touches || event.touches.length === 0) return

    this.touchStartX = event.touches[0].clientX
    this.touchCurrentX = this.touchStartX
  }

  touchMove(event) {
    if (window.innerWidth >= 768) return
    if (!event.touches || event.touches.length === 0) return

    this.touchCurrentX = event.touches[0].clientX
  }

  touchEnd() {
    if (window.innerWidth >= 768) return
    if (this.touchStartX === null || this.touchCurrentX === null) return

    const distance = this.touchCurrentX - this.touchStartX
    const swipeThreshold = 40

    if (Math.abs(distance) >= swipeThreshold) {
      if (distance < 0) {
        this.next()
      } else {
        this.prev()
      }
    }

    this.touchStartX = null
    this.touchCurrentX = null
  }

  stop(event) {
    event.stopPropagation()
  }
}
