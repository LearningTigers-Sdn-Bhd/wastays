# frozen_string_literal: true

module PanelsUI
  # A searchable single-select progressively enhanced by Tom Select.
  #
  # The native <select> remains the source of truth for validation, change
  # events, and form submission. Without JavaScript it remains visible; once
  # enhanced, Tom Select supplies the searchable combobox interaction while
  # PanelsUI supplies all visual styling.
  class Combobox < PanelsUI::BaseComponent
    SIZES = FormField::SIZES

    def initialize(form:, attribute:, choices:, id: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, size: :md, include_blank: false, prompt: nil,
                   selected: nil, placeholder: nil, max_options: nil, class: nil, **attributes)
      raise ArgumentError, "Comboboxes require choices" if choices.blank?

      @form = form
      @attribute = attribute
      @choices = choices
      @id = id
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @size = SIZES.include?(size) ? size : :md
      @include_blank = include_blank
      @prompt = prompt
      @selected = selected
      @placeholder = placeholder
      @max_options = max_options
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def native_id = @id || @form.field_id(@attribute)
    def root_id = "#{native_id}-combobox"
    def placeholder_text = @placeholder || @prompt || "Search and select…"

    def native_component
      PanelsUI::NativeSelect.new(
        form: @form,
        attribute: @attribute,
        choices: @choices,
        id: native_id,
        described_by: @described_by,
        invalid: @invalid,
        required: @required,
        disabled: @disabled,
        size: @size,
        include_blank: @include_blank,
        prompt: @prompt,
        selected: @selected,
        class: "panel-combobox__native",
        data: {
          panels_ui__combobox_target: "native",
          action: "change->panels-ui--combobox#syncFromNative"
        }
      )
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        id: root_id,
        class: tw_merge("panel-combobox", @class),
        data: data.merge(
          {
            controller: [ data.delete(:controller), "panels-ui--combobox" ].compact.join(" "),
            panels_ui__combobox_placeholder_value: placeholder_text,
            # Absent by default so Tom Select stays unlimited; a caller-supplied cap
            # is opt-in. Omitted entirely when nil to avoid a "0" (= show nothing).
            panels_ui__combobox_max_options_value: @max_options,
            size: @size,
            invalid: @invalid.to_s,
            disabled: @disabled.to_s
          }.compact
        )
      )
    end
  end
end
