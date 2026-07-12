# frozen_string_literal: true

module PanelsUI
  # A custom-scrollbar overlay modelled after shadcn/Radix ScrollArea (railsblocks).
  # The OS scrollbar is hidden and a draggable, auto-hiding thumb is painted on top,
  # while native scrolling (wheel, touch, keyboard) is preserved untouched.
  #
  #   <%= render PanelsUI::ScrollArea.new(height: "h-72", scroll_fade: :y) do %>
  #     <%= render "bookings/list" %>
  #   <% end %>
  #
  # The server renders the four structural parts (root / viewport / scrollbar / thumb)
  # and the accessible relationships; the scoped panels-ui--scroll-area controller owns
  # measurement, thumb sizing, dragging, click-to-jump, and auto-hide.
  class ScrollArea < PanelsUI::BaseComponent
    ORIENTATIONS = %i[vertical horizontal both].freeze
    FADES = %i[none y x both].freeze

    style base: "panel-scroll-area"

    def initialize(orientation: :vertical, scroll_fade: :none, hide_delay: 600,
                   height: nil, max_height: nil, class: nil, viewport_class: nil,
                   **attributes)
      @orientation = ORIENTATIONS.include?(orientation.to_sym) ? orientation.to_sym : :vertical
      @scroll_fade = FADES.include?(scroll_fade.to_sym) ? scroll_fade.to_sym : :none
      @hide_delay = hide_delay.to_i
      @height = height
      @max_height = max_height
      @class = binding.local_variable_get(:class)
      @viewport_class = viewport_class
      @attributes = attributes
    end

    def vertical? = @orientation == :vertical || @orientation == :both
    def horizontal? = @orientation == :horizontal || @orientation == :both

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || attributes.delete("data") || {}

      attributes.merge(
        class: class_for(class_override: @class),
        data: data.merge(
          controller: controller_names(data),
          orientation: @orientation,
          scroll_fade: @scroll_fade,
          panels_ui__scroll_area_target: "root",
          panels_ui__scroll_area_hide_delay_value: @hide_delay,
          action: "mouseenter->panels-ui--scroll-area#onRootMouseEnter " \
                  "mouseleave->panels-ui--scroll-area#onRootMouseLeave"
        ).compact
      )
    end

    def viewport_attributes
      {
        class: tw_merge("panel-scroll-area__viewport", @height, @max_height, @viewport_class),
        tabindex: "0",
        data: {
          panels_ui__scroll_area_target: "viewport",
          action: "scroll->panels-ui--scroll-area#onViewportScroll"
        }
      }
    end

    def scrollbar_attributes(axis)
      {
        class: "panel-scroll-area__scrollbar",
        aria: { hidden: "true" },
        data: {
          orientation: axis,
          panels_ui__scroll_area_target: "scrollbar",
          action: "click->panels-ui--scroll-area#onScrollbarClick"
        }
      }
    end

    def thumb_attributes(axis)
      {
        class: "panel-scroll-area__thumb",
        aria: { hidden: "true" },
        data: {
          orientation: axis,
          panels_ui__scroll_area_target: "thumb",
          action: "mousedown->panels-ui--scroll-area#onThumbMouseDown"
        }
      }
    end

    private

    def controller_names(data)
      caller_controller = data.delete(:controller) || data.delete("controller")
      [ caller_controller, "panels-ui--scroll-area" ].compact.join(" ")
    end
  end
end
