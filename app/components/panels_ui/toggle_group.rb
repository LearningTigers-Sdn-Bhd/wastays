# frozen_string_literal: true

module PanelsUI
  # A compact group of two-state buttons supporting either one or many selected
  # values. Selection is DOM-owned after render and can optionally mirror into
  # Rails-compatible hidden inputs.
  class ToggleGroup < PanelsUI::BaseComponent
    TYPES = %i[single multiple].freeze
    VARIANTS = PanelsUI::Toggle::VARIANTS
    SIZES = PanelsUI::Toggle::SIZES
    ICON_SIZES = PanelsUI::Toggle::ICON_SIZES
    ORIENTATIONS = %i[horizontal vertical].freeze
    SPACINGS = [ 0, 1, 2 ].freeze
    AUTO_VALUE = Object.new.freeze

    class Item < PanelsUI::BaseComponent
      attr_reader :value

      def initialize(value:, disabled: false, aria_label: nil, class: nil, **attributes)
        @value = value.to_s
        @disabled = disabled
        @aria_label = aria_label
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def configure(group_id:, selected:, group_disabled:, variant:, size:, tabindex:)
        @group_id = group_id
        @selected = selected
        @group_disabled = group_disabled
        @variant = variant
        @size = size
        @tabindex = tabindex
      end

      def disabled? = @disabled || @group_disabled

      def accessible_label
        aria = @attributes[:aria] || @attributes["aria"] || {}
        @aria_label.presence || aria[:label].presence || aria["label"].presence
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || attributes.delete("data") || {}
        aria = attributes.delete(:aria) || attributes.delete("aria") || {}
        action = data.delete(:action) || data.delete("action")
        aria[:label] ||= @aria_label

        tag.button(
          content,
          **attributes.merge(
            type: "button",
            disabled: disabled?,
            tabindex: @tabindex,
            class: tw_merge("panel-toggle panel-toggle-group__item", @class),
            aria: aria.merge(pressed: @selected.to_s).compact,
            data: data.merge(
              slot: "toggle-group-item",
              value: @value,
              state: (@selected ? "on" : "off"),
              variant: @variant,
              size: @size,
              icon_only: (ICON_SIZES.include?(@size) ? "true" : nil),
              panels_ui__toggle_group_target: "item",
              action: [ "click->panels-ui--toggle-group#toggle", action ].compact.join(" ")
            ).compact
          )
        )
      end
    end

    renders_many :items, ->(**args) { Item.new(**args) }

    def initialize(type: :single, value: AUTO_VALUE, variant: :default, size: :md,
                   orientation: :horizontal, spacing: 2, required: false, disabled: false,
                   aria_label: nil, form: nil, attribute: nil, name: nil, class: nil,
                   **attributes)
      validate_source!(form, attribute, name)
      @type = normalize_option!(:type, type, TYPES)
      @variant = normalize_option!(:variant, variant, VARIANTS)
      @size = normalize_option!(:size, size, SIZES)
      @orientation = normalize_option!(:orientation, orientation, ORIENTATIONS)
      @spacing = normalize_spacing!(spacing)
      @form = form
      @attribute = attribute
      @name = name
      @value = value
      @required = required
      @disabled = disabled
      @aria_label = aria_label
      @class = binding.local_variable_get(:class)
      @attributes = attributes
      @id = @attributes[:id] || @attributes["id"] || generated_id
    end

    def before_render
      validate_and_configure!
    end

    def call
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || attributes.delete("data") || {}
      aria = attributes.delete(:aria) || attributes.delete("aria") || {}
      attributes.delete(:id)
      attributes.delete("id")
      controller = data.delete(:controller) || data.delete("controller")
      action = data.delete(:action) || data.delete("action")

      tag.div(
        safe_join([ safe_join(items), hidden_inputs ].compact),
        **attributes.merge(
          id: @id,
          role: "group",
          class: tw_merge("panel-toggle-group", @class),
          aria: aria.merge(
            label: @aria_label,
            orientation: @orientation,
            required: (@required ? "true" : nil),
            disabled: (@disabled ? "true" : nil)
          ).compact,
          data: data.merge(
            slot: "toggle-group",
            controller: [ controller, "panels-ui--toggle-group" ].compact.join(" "),
            action: [ action, "keydown->panels-ui--toggle-group#onKeydown" ].compact.join(" "),
            type: @type,
            variant: @variant,
            size: @size,
            orientation: @orientation,
            spacing: @spacing,
            required: @required.to_s,
            disabled: @disabled.to_s
          )
        )
      )
    end

    private

    def validate_source!(form, attribute, name)
      return if form.nil? && attribute.nil? && name.nil?
      return if !form.nil? && attribute.present? && name.nil?
      return if form.nil? && attribute.nil? && name.present?

      raise ArgumentError, "Toggle groups require form: and attribute:, name:, or neither"
    end

    def normalize_option!(label, value, allowed)
      normalized = value.respond_to?(:to_sym) ? value.to_sym : value
      return normalized if allowed.include?(normalized)

      raise ArgumentError, "Toggle group #{label} must be one of: #{allowed.join(', ')}"
    end

    def normalize_spacing!(value)
      normalized = Integer(value)
      return normalized if SPACINGS.include?(normalized)

      raise ArgumentError
    rescue ArgumentError, TypeError
      raise ArgumentError, "Toggle group spacing must be one of: #{SPACINGS.join(', ')}"
    end

    def validate_and_configure!
      raise ArgumentError, "Toggle groups require an aria_label" if @aria_label.blank?
      raise ArgumentError, "Toggle groups require at least one item" if items.empty?
      raise ArgumentError, "Toggle group item values cannot be blank" if items.any? { |item| item.value.blank? }
      raise ArgumentError, "Toggle group item values must be unique" unless items.map(&:value).uniq.size == items.size
      if ICON_SIZES.include?(@size) && items.any? { |item| item.accessible_label.blank? }
        raise ArgumentError, "Icon-only toggle group items require an aria_label or aria: { label: ... }"
      end

      @selected_values = resolved_values
      missing = @selected_values - items.map(&:value)
      raise ArgumentError, "Toggle group selected values must match an item" if missing.any?

      tabbable = items.find { |item| @selected_values.include?(item.value) && !item.disabled? } ||
                 items.find { |item| !item.disabled? }

      items.each do |item|
        item.configure(
          group_id: @id,
          selected: @selected_values.include?(item.value),
          group_disabled: @disabled,
          variant: @variant,
          size: @size,
          tabindex: (item == tabbable ? "0" : "-1")
        )
      end
    end

    def resolved_values
      raw = @value.equal?(AUTO_VALUE) ? builder_value : @value
      if @type == :multiple
        Array(raw).compact.map(&:to_s).reject(&:blank?).uniq
      elsif raw.is_a?(Array)
        raise ArgumentError, "Single toggle groups require a scalar value"
      else
        raw.nil? || raw.to_s.blank? ? [] : [ raw.to_s ]
      end
    end

    def builder_value
      return nil unless builder_source?

      object = @form.object
      object.public_send(@attribute) if object&.respond_to?(@attribute)
    end

    def hidden_inputs
      return unless form_backed?

      @type == :single ? single_hidden_input : multiple_hidden_inputs
    end

    def single_hidden_input
      tag.input(
        type: "hidden",
        name: input_name,
        value: @selected_values.first.to_s,
        data: { panels_ui__toggle_group_target: "input" }
      )
    end

    def multiple_hidden_inputs
      fields = [ tag.input(type: "hidden", name: multiple_input_name, value: "") ]
      fields.concat(items.map do |item|
        tag.input(
          type: "hidden",
          name: multiple_input_name,
          value: item.value,
          disabled: !@selected_values.include?(item.value),
          data: {
            panels_ui__toggle_group_target: "input",
            value: item.value
          }
        )
      end)
      safe_join(fields)
    end

    def builder_source? = !@form.nil?
    def form_backed? = builder_source? || !@name.nil?
    def input_name = builder_source? ? @form.field_name(@attribute) : @name

    def multiple_input_name
      builder_source? ? @form.field_name(@attribute, multiple: true) : @name.to_s.delete_suffix("[]") + "[]"
    end

    def generated_id
      if builder_source?
        "#{@form.field_id(@attribute)}-toggle-group"
      elsif @name.present?
        "#{sanitize_name(@name)}-toggle-group"
      else
        "toggle-group-#{object_id}"
      end
    end

    def sanitize_name(name)
      name.to_s.gsub(/\]\[|\[|\]/, "_").gsub(/[^A-Za-z0-9_:-]/, "_").squeeze("_").delete_suffix("_")
    end
  end
end
