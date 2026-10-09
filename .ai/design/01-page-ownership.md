# Page ownership

`panel-page` owns the portal content viewport, including its width, height,
screen-edge padding, workspace behavior, and mobile-navigation clearance.

- Do not override, duplicate, cap, or compensate for `panel-page`.
- Do not add page-level `max-w-*`, replacement padding, negative margins, or
  arbitrary width and height values.
- Pages control only their internal layout.
