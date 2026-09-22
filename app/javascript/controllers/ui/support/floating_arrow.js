// Shared @floating-ui arrow placement for PanelsUI floating surfaces (tooltip, popover).
//
// Not named `*_controller.js`, so Stimulus's `lazyLoadControllersFrom("controllers")`
// skips it — it's a plain support module imported by the individual controllers.
//
// Implements Floating UI's "bordered arrow" technique: a rotated square that paints over
// the bubble's border. Its `background: inherit` fill masks the seam underneath, and only
// the two outward-facing edges are given a border color so the caret continues the bubble
// outline. Pair with the `arrow({ element, padding })` middleware and pass its
// `middlewareData.arrow` here.

const OPPOSITE_SIDE = { top: "bottom", right: "left", bottom: "top", left: "right" }

// The two rotated-square edges that form the visible caret tip, per attach side.
const ARROW_BORDER_SIDES = {
  bottom: ["Right", "Bottom"],
  top: ["Top", "Left"],
  right: ["Top", "Right"],
  left: ["Bottom", "Left"]
}

// Position and border-color the caret. `placement` is the *resolved* placement from
// computePosition (post flip/shift); `data` is `middlewareData.arrow` ({ x?, y? }).
export function positionArrow(arrowEl, placement, data) {
  if (!arrowEl || !data) return

  const side = OPPOSITE_SIDE[placement.split("-")[0]]
  const borderColor = getComputedStyle(arrowEl.parentElement).borderColor
  Object.assign(arrowEl.style, {
    left: data.x != null ? `${data.x}px` : "",
    top: data.y != null ? `${data.y}px` : "",
    right: "",
    bottom: "",
    [side]: `${-arrowEl.offsetWidth / 2}px`
  })

  // Border only on the two edges that face outward, so the caret continues the bubble
  // outline while its matching fill masks the bubble border underneath.
  for (const edge of ["Top", "Right", "Bottom", "Left"]) {
    arrowEl.style[`border${edge}Color`] = "transparent"
  }
  for (const edge of ARROW_BORDER_SIDES[side]) {
    arrowEl.style[`border${edge}Color`] = borderColor
  }
}
