# frozen_string_literal: true

module PanelsUI
  # A text-only tooltip: wraps a trigger and reveals a short label on hover/focus.
  #
  #   <%= render PanelsUI::Tooltip.new(text: "Copy to clipboard") do %>
  #     <%= render PanelsUI::Button.new(...) %>
  #   <% end %>
  #
  # The trigger is the block content; positioning, ARIA wiring, and dismissal are
  # handled by the panels-ui--tooltip Stimulus controller (mirrors DropdownMenu).
  class Tooltip < PanelsUI::BaseComponent
    PLACEMENTS = %i[
      top top_start top_end right right_start right_end
      bottom bottom_start bottom_end left left_start left_end
    ].freeze

    def initialize(text:, placement: :top, offset: 6, delay: 120, arrow: true,
                   id: nil, class: nil, root_class: nil)
      @text = text
      @placement = PLACEMENTS.include?(placement) ? placement : :top
      @offset = offset.to_f
      @delay = delay.to_i
      @arrow = arrow
      @id = id || "tooltip-#{object_id}"
      @class = binding.local_variable_get(:class)
      @root_class = root_class
    end

    def arrow? = @arrow

    def tooltip_id = @id
    def floating_placement = @placement.to_s.tr("_", "-")
  end
end
