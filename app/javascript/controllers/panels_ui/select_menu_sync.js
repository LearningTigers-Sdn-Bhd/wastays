// A PanelsUI select menu renders its own trigger over a native <select>, so a
// controller that writes to that select has to tell the menu to redraw. Three
// controllers were each rediscovering the same closest()/getController lookup.

export function selectMenuFor(application, select) {
  const root = select?.closest("[data-controller~='panels-ui--select-menu']")
  if (!root) return null

  return application.getControllerForElementAndIdentifier(root, "panels-ui--select-menu")
}

// Point the menu back at whatever the native select now holds.
export function syncSelectMenu(application, select) {
  selectMenuFor(application, select)?.syncFromNative()
}
