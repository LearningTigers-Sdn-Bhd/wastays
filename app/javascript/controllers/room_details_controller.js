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
    const roomSortOrder = ["General", "In Room", "Bathroom", "Kitchen", "Security", "Outside", "View" ]
    if (roomAmenities.length > 0) {
      this.renderAmenities(roomAmenities, this.amenitiesListTarget, this.roomAmenitiesToggleTarget, roomSortOrder)
      this.amenitiesSectionTarget.classList.remove("hidden")
    } else {
      this.amenitiesSectionTarget.classList.add("hidden")
    }

    // Hotel Amenities setup
    const hotelSortOrder = ["General", "Services", "Parking", "Safety And Security", "Food And Drink", "Activities", "Outdoors", "Pets"]
    if (data.hotel_amenities && data.hotel_amenities.length > 0) {
      this.renderAmenities(data.hotel_amenities, this.hotelAmenitiesListTarget, this.hotelAmenitiesToggleTarget, hotelSortOrder)
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

  renderAmenities(amenities, listTarget, toggleTarget, customOrder = []) {
    listTarget.innerHTML = ""
    if (amenities.length === 0) return

    // Group by category
    const grouped = amenities.reduce((acc, a) => {
      const cat = a.category || "General"
      if (!acc[cat]) acc[cat] = []
      acc[cat].push(a)
      return acc
    }, {})

    const amenityTemplate = document.getElementById("amenity-item-template")
    const categoryTemplate = document.getElementById("amenity-category-template")
    
    const categoryLimit = 1
    const itemLimit = 10
    let categoryIndex = 0
    let totalAmenities = 0

    // Sort categories for consistency
    const sortedCategories = Object.keys(grouped).sort((a, b) => {
      const indexA = customOrder.indexOf(a)
      const indexB = customOrder.indexOf(b)
      
      if (indexA !== -1 && indexB !== -1) return indexA - indexB
      if (indexA !== -1) return -1
      if (indexB !== -1) return 1
      return a.localeCompare(b)
    })

    sortedCategories.forEach(categoryName => {
      const items = grouped[categoryName]
      const categoryClone = document.importNode(categoryTemplate.content, true)
      const categoryContainer = categoryClone.querySelector("div")
      const iconContainer = categoryClone.querySelector("[data-category-icon]")
      const nameContainer = categoryClone.querySelector("[data-category-name]")
      const itemsList = categoryClone.querySelector("[data-amenity-list]")

      nameContainer.textContent = categoryName
      if (items[0] && items[0].category_icon) {
        iconContainer.innerHTML = items[0].category_icon
      }

      if (categoryIndex >= categoryLimit) {
        categoryContainer.classList.add("hidden", "extra-amenity-category")
      }

      items.forEach((amenity, itemIndex) => {
        const itemClone = document.importNode(amenityTemplate.content, true)
        const itemContainer = itemClone.firstElementChild
        const nameElement = itemContainer.querySelector("[data-amenity-name]") || itemContainer
        if (nameElement) nameElement.textContent = amenity.name

        const isExtra = (categoryIndex >= categoryLimit) || (itemIndex >= itemLimit)
        if (isExtra) {
          itemContainer.classList.add("hidden", "extra-amenity-item")
        }

        itemsList.appendChild(itemContainer)
        totalAmenities++
      })

      listTarget.appendChild(categoryContainer)
      categoryIndex++
    })

    const hasMore = totalAmenities > itemLimit || Object.keys(grouped).length > categoryLimit

    if (hasMore && toggleTarget) {
      toggleTarget.classList.remove("hidden")
      this.setToggleLabel(toggleTarget, true, totalAmenities)
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
    const extras = listTarget.querySelectorAll(".extra-amenity-item, .extra-amenity-category")
    if (extras.length === 0) return

    const isShowingMore = extras[0].classList.contains("hidden")
    const totalCount = listTarget.querySelectorAll("[data-amenity-name]").length

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
