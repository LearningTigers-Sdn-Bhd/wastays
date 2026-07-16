# frozen_string_literal: true

# Shared TailwindMerge instance for merging conflicting Tailwind classes
# server-side — primarily for PanelsUI ViewComponent variants, where a
# component's base classes get overridden by variant/size classes and a caller's
# `class:` override, and the *last* wins.
#
# A single shared instance is intentional: the merger builds a large config once
# and keeps an internal LRU cache, so reusing it (rather than `.new` per call)
# shares that cache. Do NOT freeze it — the cache mutates on use.
#
# Zero custom config is needed for the design-token system. Tailwind v4's color
# scale validator is `IS_ANY`, so token utilities already merge as conflicts out
# of the box — verified against this app's tokens:
#   bg-primary bg-card                             => bg-card
#   text-muted-foreground text-primary-foreground => text-primary-foreground
#   border-border border-border-interactive       => border-border-interactive
#   ring-ring ring-primary                        => ring-primary
# as do all standard scales (rounded-*, px-*, gap-*, …).
#
# Known limitation: custom `@utility` classes in app/assets/tailwind/application.css
# that are NOT theme-namespaced — the z-index aliases (z-modal, z-toast, z-popover, …)
# and named durations (duration-fast, duration-base) — are not recognised as conflict
# groups, so two competing ones in a single merge won't dedupe. These are set once per
# element in practice, so don't pass two competing ones through the same merge.
TW_MERGE = TailwindMerge::Merger.new

module TailwindMergeHelper
  # Merge any mix of strings / arrays / nils into a conflict-resolved class list.
  #   tw_merge("px-3 bg-primary", ["px-4", nil], "bg-card") # => "bg-card px-4"
  def tw_merge(*classes)
    TW_MERGE.merge(classes.flatten.compact.join(" "))
  end
end

ActiveSupport.on_load(:action_view) { include TailwindMergeHelper }
ActiveSupport.on_load(:view_component) { include TailwindMergeHelper }
