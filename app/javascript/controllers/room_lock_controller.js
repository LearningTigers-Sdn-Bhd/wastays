import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]
  static values = { 
    url: String,
    currentRoom: String
  }

  connect() {
    this.heartbeatInterval = null
    this.lastLockedRoom = null
    this.isLocking = false
  }

  disconnect() {
    this.release()
  }

  async lock(event) {
    if (this.isLocking) return
    this.isLocking = true

    const target = event.target
    const roomNumber = target.value
    
    // Only proceed if this is a room number field
    if (target.name && !target.name.includes("room_number")) {
      this.isLocking = false
      return
    }
    
    // If we're selecting the same room we already have a lock for, do nothing
    if (roomNumber === this.lastLockedRoom) {
      this.isLocking = false
      return
    }

    try {
      // Release old lock if we had one
      if (this.lastLockedRoom) {
        await this.releaseLock(this.lastLockedRoom)
      }

      if (!roomNumber) {
        this.lastLockedRoom = null
        this.stopHeartbeat()
        this.isLocking = false
        return
      }

      const headers = {
        'Content-Type': 'application/json'
      }

      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      if (csrfToken) {
        headers['X-CSRF-Token'] = csrfToken
      }

      const response = await fetch(this.urlValue, {
        method: 'POST',
        headers: headers,
        body: JSON.stringify({ room_number: roomNumber })
      })

      const data = await response.json()

      if (response.ok) {
        this.lastLockedRoom = roomNumber
        this.startHeartbeat()
      } else if (response.status === 409) {
        // Locked by someone else
        this.showAlert(data.message)
        
        // Reset the selection
        target.value = this.currentRoomValue || ""
        this.lastLockedRoom = null
        this.stopHeartbeat()
      }
    } catch (error) {
      console.error("[RoomLock] request failed:", error)
    } finally {
      this.isLocking = false
    }
  }

  showAlert(message) {
    const modal = document.getElementById('room-lock-alert-modal')
    const msgElement = document.getElementById('room-lock-alert-message')
    const closeBtn = document.getElementById('room-lock-alert-close')

    if (!modal || !msgElement || !closeBtn) {
      alert(message)
      return
    }

    msgElement.textContent = message
    modal.showModal()
    
    const closeModal = (e) => {
      if (e) e.preventDefault()
      modal.close()
      closeBtn.removeEventListener('click', closeModal)
    }

    closeBtn.addEventListener('click', closeModal)
  }

  async release() {
    if (this.lastLockedRoom) {
      await this.releaseLock(this.lastLockedRoom)
      this.lastLockedRoom = null
      this.stopHeartbeat()
    }
  }

  async releaseLock(roomNumber) {
    const url = new URL(this.urlValue + "/release", window.location.origin)
    url.searchParams.append('room_number', roomNumber)

    const headers = {}
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      headers['X-CSRF-Token'] = csrfToken
    }

    await fetch(url, {
      method: 'DELETE',
      headers: headers
    })
  }

  startHeartbeat() {
    this.stopHeartbeat()
    this.heartbeatInterval = setInterval(() => {
      if (this.lastLockedRoom) {
        this.refreshLock(this.lastLockedRoom)
      }
    }, 9 * 60 * 1000) // 9 minutes
  }

  stopHeartbeat() {
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval)
      this.heartbeatInterval = null
    }
  }

  async refreshLock(roomNumber) {
    const headers = {
      'Content-Type': 'application/json'
    }
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      headers['X-CSRF-Token'] = csrfToken
    }

    await fetch(this.urlValue, {
      method: 'POST',
      headers: headers,
      body: JSON.stringify({ room_number: roomNumber })
    })
  }
}
