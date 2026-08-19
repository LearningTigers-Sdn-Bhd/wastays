# frozen_string_literal: true

# A tiny cva-style variant DSL, shared by the app's component libraries.
#
# A component declares its styling once with `style`, then resolves a concrete,
# conflict-merged class string at render time with `class_for` — base classes,
# the selected variant/size classes, and the caller's `class:` override are
# combined and de-duplicated through `tw_merge` (see
# config/initializers/tailwind_merge.rb), so the last-declared utility wins.
#
#   class Button < PanelsUI::BaseComponent
#     style base: "inline-flex items-center rounded-md",
#           variants: {
#             variant: { solid: "bg-primary text-primary-foreground", ghost: "text-foreground hover:bg-muted" },
#             size:    { sm: "h-8 px-3 text-sm", md: "h-10 px-4" },
#           },
#           defaults: { variant: :solid, size: :md }
#   end
#
#   class_for(variant: :ghost, class_override: "w-full") # merged string, ghost + md + w-full
#
# Lives outside both libraries on purpose: PublicUI dresses guest-facing pages
# that are explicitly out of DESIGN.md scope, so it must not inherit from the
# portal's PanelsUI to borrow this.
module TailwindVariants
  extend ActiveSupport::Concern

  class_methods do
    attr_reader :style_config

    def style(base: "", variants: {}, defaults: {})
      @style_config = { base: base, variants: variants, defaults: defaults }
    end

    # Subclasses inherit the parent's style unless they declare their own.
    def inherited(subclass)
      super
      subclass.instance_variable_set(:@style_config, @style_config)
    end
  end

  # Resolve declared style + variant selections (+ caller override) into one
  # conflict-merged class string. Unknown/nil selections fall back to defaults.
  def class_for(class_override: nil, **selected)
    config = self.class.style_config
    return tw_merge(class_override) unless config

    chosen = config[:defaults].merge(selected.compact)
    parts  = [ config[:base] ]
    chosen.each do |group, value|
      variants = config[:variants][group]
      next unless variants

      resolved = variants.key?(value) ? value : config[:defaults][group]
      parts << variants[resolved]
    end
    parts << class_override
    tw_merge(parts)
  end
end
