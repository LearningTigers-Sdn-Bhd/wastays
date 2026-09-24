# frozen_string_literal: true

module PanelsUI
  # A toggle switch. Behaviourally it is a checkbox — same on/off value, hidden
  # companion field, and form/name sourcing — so it inherits all of that from
  # ToggleField. Only the presentation (a track + thumb via panel/switch.css) and
  # the ARIA role differ, giving assistive tech the on/off "switch" semantics.
  class Switch < PanelsUI::ToggleField
    VARIANTS = %i[default card icon].freeze
    # The "on" colour. `default` is the product's primary; `success` is for a
    # switch whose on state is a permission being granted, where green is what
    # an operator reads as "allowed" without having to read the label twice.
    # Off is grey either way -- an inactive permission carries no colour.
    TONES = %i[default success].freeze

    def initialize(off_icon: nil, on_icon: nil, tone: :default, **options)
      @off_icon = off_icon
      @on_icon = on_icon
      @tone = TONES.include?(tone) ? tone : :default
      super(**options)
    end

    def before_render
      return unless @variant == :icon
      return if @off_icon.present? && @on_icon.present?

      raise ArgumentError, "Icon switches require off_icon: and on_icon:"
    end

    def call
      return super unless @variant == :icon

      tag.label(**wrapper_attributes) do
        safe_join([ icon_control, label_content ])
      end
    end

    private

    def wrapper_attributes
      attributes = super
      attributes.merge(data: attributes[:data].merge(tone: @tone))
    end

    def css_prefix = "panel-switch"
    def control_noun = "Switches"
    def control_role = "switch"

    # Unlike a collection checkbox, a standalone switch owns one scalar value;
    # its off state must therefore submit explicitly as well.
    def tag_control
      safe_join([
        # id: nil so the companion does not claim the id the visible control
        # needs — hidden_field_tag would otherwise derive the same one from the
        # shared name and duplicate it on the page.
        hidden_field_tag(@name, @unchecked_value, id: nil, disabled: @disabled, autocomplete: "off"),
        super
      ])
    end

    def icon_control
      tag.span(class: "panel-switch__control") do
        safe_join([
          control,
          state_icon(@off_icon, "off"),
          state_icon(@on_icon, "on")
        ])
      end
    end

    def state_icon(name, state)
      tag.span(
        helpers.app_icon(name, aria: { hidden: "true" }),
        class: "panel-switch__state-icon",
        data: { state: state },
        aria: { hidden: "true" }
      )
    end
  end
end
