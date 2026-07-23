# frozen_string_literal: true

module PanelsUI
  # A free-form text input with remote suggestions. The input remains the form
  # source of truth; choosing a suggestion emits a bubbling
  # `panels-ui:autocomplete-select` event with the selected result payload.
  class Autocomplete < PanelsUI::BaseComponent
    SIZES = FormField::SIZES

    def initialize(form:, attribute:, endpoint:, type: :text, id: nil, described_by: nil,
                   invalid: false, required: false, disabled: false, readonly: false,
                   size: :md, placeholder: nil, min_length: 2, debounce: 180,
                   empty_text: "No matching results", class: nil, **attributes)
      raise ArgumentError, "Autocompletes require an endpoint" if endpoint.blank?

      @form = form
      @attribute = attribute
      @endpoint = endpoint
      @type = type
      @id = id
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @readonly = readonly
      @size = SIZES.include?(size) ? size : :md
      @placeholder = placeholder
      @min_length = [ min_length.to_i, 0 ].max
      @debounce = [ debounce.to_i, 0 ].max
      @empty_text = empty_text
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def native_id = @id || @form.field_id(@attribute)
    def root_id = "#{native_id}-autocomplete"
    def listbox_id = "#{native_id}-autocomplete-listbox"
    def status_id = "#{native_id}-autocomplete-status"

    def input_component
      PanelsUI::Input.new(
        form: @form,
        attribute: @attribute,
        type: @type,
        id: native_id,
        described_by: @described_by,
        invalid: @invalid,
        required: @required,
        disabled: @disabled,
        readonly: @readonly,
        size: @size,
        placeholder: @placeholder,
        autocomplete: "off",
        role: "combobox",
        data: {
          panels_ui__autocomplete_target: "input",
          action: "input->panels-ui--autocomplete#search focus->panels-ui--autocomplete#open keydown->panels-ui--autocomplete#onKeydown"
        },
        aria: {
          autocomplete: "list",
          expanded: "false",
          controls: listbox_id,
          haspopup: "listbox"
        }
      )
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        id: root_id,
        class: tw_merge("panel-autocomplete", @class),
        data: data.merge(
          controller: [ data.delete(:controller), "panels-ui--autocomplete" ].compact.join(" "),
          panels_ui__autocomplete_endpoint_value: @endpoint,
          panels_ui__autocomplete_min_length_value: @min_length,
          panels_ui__autocomplete_debounce_value: @debounce,
          panels_ui__autocomplete_empty_text_value: @empty_text,
          action: [ data.delete(:action), "pointerdown@window->panels-ui--autocomplete#onWindowPointerDown" ].compact.join(" "),
          size: @size,
          invalid: @invalid.to_s,
          disabled: @disabled.to_s,
          readonly: @readonly.to_s
        )
      )
    end
  end
end
