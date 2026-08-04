# frozen_string_literal: true

module PanelsUI
  # Abstract base for label-wrapped boolean/enumerable inputs — checkbox, switch,
  # and radio. It owns everything that is not specific to a given control type:
  # the label wrapper, description/error rendering, required marker, id/aria wiring,
  # and error resolution from either a form builder or the object's errors.
  #
  # Subclasses supply the pieces that actually differ:
  #   * `css_prefix`  — BEM-ish class root, e.g. "panel-checkbox"
  #   * `control_noun` — human name used in validation messages, e.g. "Checkboxes"
  #   * `control_role` — optional ARIA role for the input (nil by default)
  #   * `builder_control` / `tag_control` — the concrete <input> for form/name sources
  #   * `control_data`  — hook to augment the input's data attributes
  #
  # It is not rendered directly; instantiating it raises through the abstract hooks.
  class ToggleField < PanelsUI::BaseComponent
    SIZES = FormField::SIZES
    VARIANTS = %i[default card].freeze
    AUTO_ERROR = Object.new.freeze

    def initialize(form: nil, attribute: nil, name: nil, label:, description: nil, error: AUTO_ERROR,
                   id: nil, value: "1", checked: nil, unchecked_value: "0", required: false,
                   required_marker: true,
                   disabled: false, size: :md, variant: :default, class: nil, **attributes)
      validate_source!(form, attribute, name)
      raise ArgumentError, "#{control_noun} require a label" if label.blank?

      @form = form
      @attribute = attribute
      @name = name
      @label = label
      @description = description
      @error = error
      @id = id
      @value = value
      @checked = checked
      @unchecked_value = unchecked_value
      @required = required
      @required_marker = required_marker
      @disabled = disabled
      @size = self.class::SIZES.include?(size) ? size : :md
      @variant = self.class::VARIANTS.include?(variant) ? variant : :default
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def call
      tag.label(**wrapper_attributes) do
        safe_join([ control, label_content ])
      end
    end

    private

    # ---- Subclass hooks -----------------------------------------------------

    def css_prefix = raise NotImplementedError, "#{self.class} must define #css_prefix"
    def control_noun = raise NotImplementedError, "#{self.class} must define #control_noun"
    def control_role = nil
    def control_data(data) = data

    def builder_control
      @form.check_box(@attribute, builder_options, @value, @unchecked_value)
    end

    def tag_control
      check_box_tag(@name, @value, @checked || false, **input_attributes)
    end

    def builder_options
      options = input_attributes.merge(include_hidden: include_hidden?)
      options[:checked] = @checked unless @checked.nil?
      options
    end

    # ---- Shared scaffolding -------------------------------------------------

    def validate_source!(form, attribute, name)
      builder_source = form.present? || attribute.present?
      tag_source = name.present?

      return if form.present? && attribute.present? && !tag_source
      return if !builder_source && tag_source

      raise ArgumentError, "#{control_noun} require either form: and attribute:, or name:"
    end

    def control
      builder_source? ? builder_control : tag_control
    end

    def input_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}
      aria = attributes.delete(:aria) || {}
      attributes.delete(:include_hidden)
      described_by = [ aria.delete(:describedby) || aria.delete("describedby"), generated_description_id ].compact.join(" ").presence

      attributes.merge(
        id: @id || attributes.delete(:id) || control_id,
        class: tw_merge("#{css_prefix}__input", @class),
        role: control_role,
        required: @required || attributes.delete(:required),
        disabled: @disabled || attributes.delete(:disabled),
        data: control_data(data),
        aria: aria.merge(describedby: described_by, invalid: (invalid? ? "true" : nil)).compact
      ).compact
    end

    def wrapper_attributes
      {
        for: control_id,
        class: css_prefix,
        data: { size: @size, variant: @variant, invalid: invalid?.to_s, disabled: @disabled.to_s }
      }
    end

    def label_content
      tag.span(class: "#{css_prefix}__content") do
        safe_join([
          tag.span(class: "#{css_prefix}__label") do
            safe_join([ @label, (required_content if @required && @required_marker) ].compact)
          end,
          (tag.span(@description, id: description_id, class: "#{css_prefix}__description") if description?),
          (tag.span(error_message, id: error_id, class: "#{css_prefix}__error", role: "alert") if invalid?)
        ].compact)
      end
    end

    def required_content
      safe_join([
        tag.span("*", class: "#{css_prefix}__required", aria: { hidden: true }),
        tag.span("(required)", class: "sr-only")
      ])
    end

    def builder_source? = @form.present?
    def include_hidden? = @attributes.fetch(:include_hidden, @attributes.fetch("include_hidden", true))
    def control_id = @id || @attributes[:id] || @attributes["id"] || generated_control_id
    def generated_control_id = builder_source? ? @form.field_id(@attribute) : @name.to_s.gsub(/\]\[|\[|\]/, "_").gsub(/[^A-Za-z0-9_:-]/, "_").squeeze("_").delete_suffix("_")
    def description_id = "#{control_id}-description"
    def error_id = "#{control_id}-error"
    def error_message
      return @error unless @error.equal?(AUTO_ERROR)
      return unless @form&.object&.respond_to?(:errors)

      @form.object.errors[@attribute].first
    end
    def invalid? = error_message.present?
    def description? = @description.present? && !invalid?
    def generated_description_id = invalid? ? error_id : (description_id if description?)
  end
end
