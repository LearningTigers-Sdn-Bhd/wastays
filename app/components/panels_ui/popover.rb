# frozen_string_literal: true

module PanelsUI
  # Click- (or hover-) triggered container that yields arbitrary content, positioned
  # like a menu with an optional caret like a tooltip. Sits between Tooltip (text-only,
  # hover) and DropdownMenu (structured menu): reuses their @floating-ui positioning and
  # the shared bordered arrow, but is NOT a menu — no roving tabindex, no menuitem roles.
  #
  # `focus: true` traps focus within the panel (Tab cycles inside, focus returns to the
  # trigger on close); kept simple — no scroll lock, no inert backdrop. A focus-trapped
  # popover always uses a click trigger.
  class Popover < PanelsUI::BaseComponent
    PLACEMENTS = %i[
      top top_start top_end right right_start right_end
      bottom bottom_start bottom_end left left_start left_end
    ].freeze
    TRIGGERS = %i[click hover].freeze

    # Click/keydown always live on the trigger button. Hover-open actions (when
    # trigger_on: :hover) live on the root wrapper instead, so moving the pointer from
    # the trigger into the panel — a DOM descendant of the root — doesn't self-close.
    class Trigger < PanelsUI::BaseComponent
      def initialize(id:, panel_id:, aria_haspopup:, variant: :secondary, size: :md,
                     aria_label: nil, unstyled: false, class: nil, **attributes)
        @id = id
        @panel_id = panel_id
        @variant = Button::VARIANTS.include?(variant) ? variant : :secondary
        @size = Button::SIZES.include?(size) ? size : :md
        @aria_label = aria_label
        @aria_haspopup = aria_haspopup
        @unstyled = ActiveModel::Type::Boolean.new.cast(unstyled)
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}
        aria = attributes.delete(:aria) || {}

        tag.button(
          content,
          **attributes.merge(
            id: @id,
            type: "button",
            class: tw_merge(("panel-button" unless @unstyled), "popover__trigger", @class),
            data: data.merge(
              variant: (@variant unless @unstyled),
              size: (@size unless @unstyled),
              panels_ui__popover_target: "trigger",
              action: "click->panels-ui--popover#toggle keydown->panels-ui--popover#onTriggerKeydown"
            ).compact,
            aria: aria.merge(
              label: @aria_label,
              haspopup: @aria_haspopup,
              expanded: "false",
              controls: @panel_id
            ).compact
          )
        )
      end
    end

    renders_one :trigger, lambda { |**args|
      Trigger.new(id: trigger_id, panel_id: panel_id, aria_haspopup: @aria_haspopup, **args)
    }

    def initialize(id:, placement: :bottom, offset: 8, delay: 120, close_delay: 0, arrow: true,
                   trigger_on: :click, focus: false, class: nil, root_class: nil,
                   role: "dialog", aria_haspopup: "dialog")
      @id = id
      @placement = PLACEMENTS.include?(placement) ? placement : :bottom
      @offset = offset.to_f
      @delay = delay.to_i
      @close_delay = close_delay.to_i
      @arrow = arrow
      @focus = ActiveModel::Type::Boolean.new.cast(focus) || false
      # A hover-open focus trap makes no sense; trapping focus forces a click trigger.
      @trigger_on = (@focus ? :click : (TRIGGERS.include?(trigger_on) ? trigger_on : :click))
      @class = binding.local_variable_get(:class)
      @root_class = root_class
      @role = role
      @aria_haspopup = aria_haspopup
    end

    def arrow? = @arrow
    def focus? = @focus
    def trigger_id = "#{@id}-trigger"
    def panel_id = "#{@id}-panel"
    def floating_placement = @placement.to_s.tr("_", "-")

    # Hover-open actions live on the root so the pointer can travel into the panel
    # (a descendant) without firing mouseleave. Empty for the default click trigger.
    def root_action
      return nil unless @trigger_on == :hover

      "mouseenter->panels-ui--popover#show mouseleave->panels-ui--popover#hide " \
        "focusin->panels-ui--popover#show focusout->panels-ui--popover#hide"
    end
  end
end
