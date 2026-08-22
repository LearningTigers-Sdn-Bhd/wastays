# frozen_string_literal: true

module PublicUI
  # Base class for every PublicUI primitive.
  #
  # PublicUI dresses the guest-facing pages (the concierge, and marketing), which
  # DESIGN.md explicitly puts outside its scope: serif headings, uppercase
  # tracking-widest eyebrows, soft 2xl panels. It shares the variant DSL with
  # PanelsUI but nothing else — a change to the portal's look must not reach a
  # page a guest sees, and the reverse.
  class BaseComponent < ViewComponent::Base
    include TailwindVariants
  end
end
