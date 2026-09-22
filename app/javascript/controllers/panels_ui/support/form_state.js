// Shared, order-independent snapshot of a form's values.
//
// Not named `*_controller.js`, so Stimulus's `lazyLoadControllersFrom` skips it —
// it's a plain support module imported by the controllers that guard unsaved work.
//
// Files are reduced to name and size: two different uploads never compare equal,
// and re-reading the bytes to tell them apart is not worth it for a dirty check.
export function serializeForm(form) {
  return Array.from(new FormData(form).entries())
    .map(([key, value]) => [key, value instanceof File ? `${value.name}:${value.size}` : String(value)])
    .sort(([aKey, aValue], [bKey, bValue]) => `${aKey}:${aValue}`.localeCompare(`${bKey}:${bValue}`))
    .map(([key, value]) => `${key}=${value}`)
    .join("&")
}
