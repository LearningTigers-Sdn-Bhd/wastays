# frozen_string_literal: true

module PanelsUI
  # An accessible group of radio buttons. Unlike a lone Radio, the group owns the
  # question label, the shared hint/error, and the role="radiogroup" semantics —
  # the individual radios only carry their own option label and description.
  #
  #   render PanelsUI::RadioGroup.new(
  #     form: form, attribute: :board,
  #     label: "Board basis",
  #     options: [
  #       { label: "Room only", value: "room_only" },
  #       { label: "Breakfast included", value: "bnb", description: "Daily buffet" },
  #       { label: "Full board", value: "full", disabled: true }
  #     ]
  #   )
  #
  # Options accept hashes ({ label:, value:, description:, disabled: }) or plain
  # [label, value] pairs.
  class RadioGroup < PanelsUI::BaseComponent
    SIZES = FormField::SIZES
    VARIANTS = Radio::VARIANTS
    ORIENTATIONS = %i[vertical horizontal].freeze
    AUTO_ERROR = Object.new.freeze

    def initialize(form: nil, attribute: nil, name: nil, label:, options:, description: nil,
                   error: AUTO_ERROR, selected: nil, id: nil, required: false, disabled: false,
                   size: :md, variant: :default, orientation: :vertical, class: nil, **attributes)
      validate_source!(form, attribute, name)
      raise ArgumentError, "Radio groups require a label" if label.blank?
      raise ArgumentError, "Radio groups require options" if options.blank?

      @form = form
      @attribute = attribute
      @name = name
      @label = label
      @options = options
      @description = description
      @error = error
      @selected = selected
      @id = id
      @required = required
      @disabled = disabled
      @size = SIZES.include?(size) ? size : :md
      @variant = VARIANTS.include?(variant) ? variant : :default
      @orientation = ORIENTATIONS.include?(orientation) ? orientation : :vertical
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      tag.fieldset(**wrapper_attributes) do
        safe_join([ legend, description_content, options_list, error_content ].compact)
      end
    end

    private

    def validate_source!(form, attribute, name)
      builder_source = form.present? || attribute.present?
      tag_source = name.present?

      return if form.present? && attribute.present? && !tag_source
      return if !builder_source && tag_source

      raise ArgumentError, "Radio groups require either form: and attribute:, or name:"
    end

    def wrapper_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), generated_description_id ].compact.join(" ").presence

      attributes.merge(
        id: group_id,
        class: tw_merge("panel-radio-group", @class),
        role: "radiogroup",
        aria: aria.merge(
          labelledby: legend_id,
          describedby: described_by,
          invalid: (invalid? ? "true" : nil),
          required: (@required ? "true" : nil)
        ).compact,
        data: data.merge(
          size: @size,
          variant: @variant,
          orientation: @orientation,
          invalid: invalid?.to_s,
          disabled: @disabled.to_s
        )
      )
    end

    def legend
      tag.legend(id: legend_id, class: "panel-radio-group__legend") do
        safe_join([ @label, (required_content if @required) ].compact)
      end
    end

    def required_content
      safe_join([
        tag.span("*", class: "panel-radio-group__required", aria: { hidden: true }),
        tag.span("(required)", class: "sr-only")
      ])
    end

    def options_list
      tag.div(class: "panel-radio-group__options") do
        safe_join(normalized_options.map { |option| render(radio_for(option)) })
      end
    end

    def radio_for(option)
      PanelsUI::Radio.new(
        **source_for(option),
        label: option.fetch(:label),
        value: option.fetch(:value),
        description: option[:description],
        checked: checked_for(option.fetch(:value)),
        required: @required,
        disabled: @disabled || option[:disabled] || false,
        size: @size,
        variant: @variant,
        error: nil
      )
    end

    # The group renders one aria-invalid on the fieldset; individual radios must
    # not each surface the object error, so a builder-sourced radio is addressed
    # by name to keep Rails from re-deriving the error, and never inherits AUTO_ERROR.
    def source_for(_option)
      builder_source? ? { form: @form, attribute: @attribute } : { name: @name }
    end

    def checked_for(value)
      return nil if @selected.nil? && builder_source?

      @selected.to_s == value.to_s
    end

    def description_content
      return unless description?

      tag.p(@description, id: description_id, class: "panel-radio-group__description")
    end

    def error_content
      return unless invalid?

      tag.p(error_message, id: error_id, class: "panel-radio-group__error", role: "alert")
    end

    def normalized_options
      @options.map do |option|
        next option if option.is_a?(Hash)

        { label: option[0], value: option[1] }
      end
    end

    def builder_source? = @form.present?
    def group_id = @id || @attributes[:id] || @attributes["id"] || generated_group_id
    def generated_group_id
      base = builder_source? ? @form.field_id(@attribute) : @name.to_s.gsub(/\]\[|\[|\]/, "_").gsub(/[^A-Za-z0-9_:-]/, "_").squeeze("_").delete_suffix("_")
      "#{base}-group"
    end
    def legend_id = "#{group_id}-legend"
    def description_id = "#{group_id}-description"
    def error_id = "#{group_id}-error"
    def error_message
      return @error unless @error.equal?(AUTO_ERROR)
      return unless @form&.object&.respond_to?(:errors)

      @form.object.errors[@attribute].first
    end
    def invalid? = error_message.present?
    # Unlike a single control, a group hint is a persistent instruction ("choose
    # one"), not a value description — so it stays under the legend even while the
    # error shows at the bottom, and aria-describedby references both.
    def description? = @description.present?
    def generated_description_id
      [ (description_id if description?), (error_id if invalid?) ].compact.join(" ").presence
    end
  end
end
