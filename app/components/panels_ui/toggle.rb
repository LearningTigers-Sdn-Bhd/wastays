# frozen_string_literal: true

module PanelsUI
  # A two-state button with optional Rails form backing. The visible button owns
  # the interaction semantics; a hidden input mirrors its state when a form
  # source is supplied.
  class Toggle < PanelsUI::BaseComponent
    VARIANTS = %i[default outline].freeze
    SIZES = PanelsUI::Button::SIZES
    ICON_SIZES = %i[icon_xs icon_sm icon icon_lg].freeze
    AUTO_PRESSED = Object.new.freeze

    def initialize(form: nil, attribute: nil, name: nil, pressed: AUTO_PRESSED,
                   value: "1", unchecked_value: "0", variant: :default, size: :md,
                   disabled: false, icon_only: false, aria_label: nil, class: nil,
                   **attributes)
      validate_source!(form, attribute, name)
      validate_option!(:variant, variant, VARIANTS)
      validate_option!(:size, size, SIZES)

      @form = form
      @attribute = attribute
      @name = name
      @pressed = resolve_pressed(pressed)
      @value = value.to_s
      @unchecked_value = unchecked_value.to_s
      @variant = variant.to_sym
      @size = size.to_sym
      @disabled = disabled
      @icon_only = icon_only || ICON_SIZES.include?(@size)
      @aria_label = aria_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def before_render
      aria = @attributes[:aria] || @attributes["aria"] || {}
      label = @aria_label.presence || aria[:label].presence || aria["label"].presence
      return unless @icon_only && label.blank?

      raise ArgumentError, "Icon-only toggles require an aria_label or aria: { label: ... }"
    end

    def call
      tag.span(**root_attributes) do
        safe_join([ toggle_button, hidden_input ].compact)
      end
    end

    private

    def validate_source!(form, attribute, name)
      return if form.nil? && attribute.nil? && name.nil?
      return if !form.nil? && attribute.present? && name.nil?
      return if form.nil? && attribute.nil? && name.present?

      raise ArgumentError, "Toggles require form: and attribute:, name:, or neither"
    end

    def validate_option!(label, value, allowed)
      normalized = value.respond_to?(:to_sym) ? value.to_sym : value
      return if allowed.include?(normalized)

      raise ArgumentError, "Toggle #{label} must be one of: #{allowed.join(', ')}"
    end

    def resolve_pressed(pressed)
      return ActiveModel::Type::Boolean.new.cast(pressed) unless pressed.equal?(AUTO_PRESSED)
      return false unless builder_source?

      object = @form.object
      raw_value = object.public_send(@attribute) if object&.respond_to?(@attribute)
      ActiveModel::Type::Boolean.new.cast(raw_value)
    end

    def root_attributes
      {
        class: "panel-toggle-root",
        data: {
          slot: "toggle-root",
          controller: "panels-ui--toggle"
        }
      }
    end

    def toggle_button
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || attributes.delete("data") || {}
      aria = attributes.delete(:aria) || attributes.delete("aria") || {}
      action = data.delete(:action) || data.delete("action")
      aria[:label] ||= @aria_label

      tag.button(
        content,
        **attributes.merge(
          id: attributes.delete(:id) || attributes.delete("id") || control_id,
          type: "button",
          disabled: @disabled,
          class: tw_merge("panel-toggle", @class),
          aria: aria.merge(pressed: @pressed.to_s).compact,
          data: data.merge(
            slot: "toggle",
            state: state,
            variant: @variant,
            size: @size,
            icon_only: (@icon_only ? "true" : nil),
            panels_ui__toggle_target: "button",
            action: [ "click->panels-ui--toggle#toggle", action ].compact.join(" ")
          ).compact
        )
      )
    end

    def hidden_input
      return unless form_backed?

      tag.input(
        type: "hidden",
        id: "#{control_id}-input",
        name: input_name,
        value: (@pressed ? @value : @unchecked_value),
        data: {
          panels_ui__toggle_target: "input",
          pressed_value: @value,
          unpressed_value: @unchecked_value
        }
      )
    end

    def builder_source? = !@form.nil?
    def form_backed? = builder_source? || !@name.nil?
    def state = @pressed ? "on" : "off"
    def input_name = builder_source? ? @form.field_name(@attribute) : @name

    def control_id
      @control_id ||= if builder_source?
        "#{@form.field_id(@attribute)}-toggle"
      elsif @name.present?
        "#{sanitize_name(@name)}-toggle"
      else
        "toggle-#{object_id}"
      end
    end

    def sanitize_name(name)
      name.to_s.gsub(/\]\[|\[|\]/, "_").gsub(/[^A-Za-z0-9_:-]/, "_").squeeze("_").delete_suffix("_")
    end
  end
end
