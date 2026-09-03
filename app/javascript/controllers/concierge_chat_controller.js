import { Controller } from "@hotwired/stimulus"

// Keeps a chat thread readable while messages arrive.
//
// Two jobs, both about not losing the reader's place. It keeps the newest
// message in view -- a chat that opens at the top of a long thread makes you
// scroll to find the answer you just asked for -- but only when you were
// already at the bottom, so a live message cannot yank the page out from under
// someone reading back through it.
//
// And it drops a broadcast for a message the page already shows. Whoever wrote
// the message gets it twice: once in the page they were redirected to, once
// down the stream they are subscribed to. The stream copy is the one to throw
// away, because the rendered page is the source of truth.
export default class extends Controller {
  static targets = ["log", "input"]

  connect() {
    this.onBeforeStreamRender = this.onBeforeStreamRender.bind(this)
    document.addEventListener("turbo:before-stream-render", this.onBeforeStreamRender)
    this.scrollToLatest()
    this.markScrollPosition()
    this.growInput()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.onBeforeStreamRender)
  }

  // The reply to a send no longer replaces the box, so emptying it is this
  // controller's job. Only on a send that worked -- a refused message is one
  // the guest may want to edit rather than retype.
  onSubmitEnd(event) {
    if (!event.detail?.success) return
    if (!this.hasInputTarget) return

    this.inputTarget.value = ""
    this.growInput()
    this.clearSuggestions()
    this.scrollToLatest()
  }

  // Enter sends, Shift+Enter breaks the line. Not while an IME is composing:
  // for anyone typing Chinese or Japanese, Enter is how a candidate is chosen,
  // and sending on it would post half a word.
  //
  // The box's *own* form, reached through the field rather than looked up in
  // the panel. Asking the panel for its first form found the menu's -- button_to
  // builds one per item and the bar comes first in the document -- so Enter
  // submitted "clear conversation", and submitting a form without its button
  // skips the confirm that hangs off the button. Enter deleted the thread
  // silently. A field always knows the form it belongs to; nothing else here
  // should be guessing.
  onInputKeydown(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    this.inputTarget.form?.requestSubmit()
  }

  // The box grows with what is being written, up to the max-height the
  // stylesheet sets, where it becomes its own small scroller. Measured from
  // zero every time: a box that has already grown reports its current height
  // as its content height, so it could never shrink again.
  growInput() {
    if (!this.hasInputTarget) return

    const input = this.inputTarget
    input.style.height = "auto"
    input.style.height = `${input.scrollHeight}px`
  }

  focusComposer() {
    if (!this.hasInputTarget) return

    this.inputTarget.focus()
  }

  clearSuggestions() {
    this.element.querySelector(".public-chat__quick-replies")?.remove()
  }

  onBeforeStreamRender(event) {
    const stream = event.target
    if (this.alreadyRendered(stream)) {
      event.preventDefault()
      return
    }

    const pinned = this.pinnedToBottom
    requestAnimationFrame(() => {
      if (pinned) this.scrollToLatest()
      this.markScrollPosition()
    })
  }

  // Only an append can duplicate: a replace or a remove is addressed at an
  // element by id and is idempotent by nature.
  alreadyRendered(stream) {
    if (stream.getAttribute("action") !== "append") return false

    const template = stream.templateElement
    if (!template) return false

    const ids = Array.from(template.content.querySelectorAll("[id]")).map((element) => element.id)
    return ids.length > 0 && ids.every((id) => document.getElementById(id))
  }

  scrollToLatest() {
    const scroller = this.scroller
    if (!scroller) return

    scroller.scrollTop = scroller.scrollHeight
    this.markScrollPosition()
  }

  // Called by the log's own scroll event as well as after anything that changes
  // its contents.
  markScrollPosition() {
    if (!this.hasLogTarget) return

    const scroller = this.scroller
    if (!scroller) return

    // A thread that fits needs no fade; one scrolled to the very top has
    // nothing hidden above it either. Anything else does, and says so.
    const hasMoreAbove = scroller.scrollHeight > scroller.clientHeight && scroller.scrollTop > 4
    this.logTarget.dataset.moreAbove = hasMoreAbove.toString()
  }

  get pinnedToBottom() {
    const scroller = this.scroller
    if (!scroller) return true

    return scroller.scrollHeight - scroller.scrollTop - scroller.clientHeight < 80
  }

  // The element that actually scrolls is not always the list: on the guest page
  // the list is its own scroll container, in the portal it sits inside one.
  // Found by looking rather than named, so neither side has to know how the
  // other is built.
  get scroller() {
    if (!this.hasLogTarget) return null

    let node = this.logTarget
    while (node && node !== document.body) {
      const overflow = getComputedStyle(node).overflowY
      if ((overflow === "auto" || overflow === "scroll") && node.scrollHeight > node.clientHeight) return node
      node = node.parentElement
    }

    return this.logTarget
  }
}
