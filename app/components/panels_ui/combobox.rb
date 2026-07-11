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
                   selected: nil, placeholder: nil, max_options: nil, empty_text: nil, class: nil, **attributes)
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
      @empty_text = empty_text
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def native_id = @id || @form.field_id(@attribute)
    def placeholder_text = @placeholder || @prompt || "Search and select…"

    # Override hooks — MultiSelect subclasses to repoint the Stimulus controller,
    # the root id/class, and the native <select multiple> flag while inheriting
    # everything else. Kept here so both components render an identical structure.
    def stimulus_identifier = "panels-ui--combobox"
    def root_id = "#{native_id}-combobox"
    def root_class = "panel-combobox"
    def native_multiple? = false

    # Extra Stimulus value data merged into the root — MultiSelect adds its
    # trigger cap here. Keyed by stimulus_identifier so the values resolve.
    def extra_root_data = {}

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
        multiple: native_multiple?,
        include_blank: @include_blank,
        prompt: @prompt,
        selected: @selected,
        class: "panel-combobox__native",
        data: {
          "#{stimulus_identifier}-target" => "native",
          action: "change->#{stimulus_identifier}#syncFromNative"
        }
      )
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        id: root_id,
        class: tw_merge(root_class, @class),
        data: data.merge(
          {
            controller: [ data.delete(:controller), stimulus_identifier ].compact.join(" "),
            "#{stimulus_identifier}-placeholder-value" => placeholder_text,
            # Absent by default so Tom Select stays unlimited; a caller-supplied cap
            # is opt-in. Omitted entirely when nil to avoid a "0" (= show nothing).
            "#{stimulus_identifier}-max-options-value" => @max_options,
            # Overrides the "No results found" text when the filter matches nothing.
            "#{stimulus_identifier}-empty-text-value" => @empty_text,
            size: @size,
            invalid: @invalid.to_s,
            disabled: @disabled.to_s
          }.merge(extra_root_data).compact
        )
      )
    end
  end
end
