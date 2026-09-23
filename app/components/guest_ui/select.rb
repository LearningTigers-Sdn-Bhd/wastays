# frozen_string_literal: true

module GuestUI
  # One choice from a list too long for radio cards, such as the guest's bank.
  #
  # Built over a real <select>, which carries the value, submits it, and is what
  # a guest without JavaScript uses. The `ui--select-menu` controller -- the one
  # PanelsUI::SelectMenu uses -- hides it and shows a trigger and a listbox that
  # mirror it. The behaviour is shared; the markup and the look are the
  # concierge's own, because GuestUI stays walled off from the portal's styles.
  #
  #   field.with_select(choices: BankCatalog.options, prompt: "Choose your bank")
  #
  # native_data goes on the native select, for a page controller that reads
  # the value or listens for its change (guest-identity, pre-checkin-document).
  class Select < GuestUI::BaseComponent
    def initialize(form:, attribute:, choices:, prompt: "Choose one", selected: nil, id: nil, labelled_by: nil,
                   described_by: nil, invalid: false, required: false, disabled: false, readonly: false,
                   native_data: {}, size: nil, class: nil, **attributes)
      raise ArgumentError, "Selects require choices" if choices.blank?

      @form = form
      @attribute = attribute
      @choices = normalize(choices)
      @prompt = prompt
      @selected = selected
      @id = id
      @labelled_by = labelled_by
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled || readonly
      @native_data = native_data
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    # The native select keeps the plain field id, so the field's <label for>
    # still points at the real form control.
    def native_id = @id || @form.field_id(@attribute)
    def trigger_id = "#{native_id}-trigger"
    def value_id = "#{native_id}-value"
    def listbox_id = "#{native_id}-listbox"
    def option_id(index) = "#{native_id}-option-#{index}"

    def selected_label = @choices.find { |choice| choice[:value].to_s == current_value }&.fetch(:label)

    private

    attr_reader :choices

    # [label, value] pairs, the shape BankCatalog.options returns, or bare values.
    def normalize(choices)
      Array(choices).map do |choice|
        choice.is_a?(Array) ? { label: choice.first, value: choice.last } : { label: choice.to_s, value: choice }
      end
    end

    # `selected` wins over the object's value, for a choice that is not the
    # stored value itself -- "Other" for a bank the guest typed in.
    def current_value
      return @selected.to_s unless @selected.nil?

      object = @form.object
      object.respond_to?(@attribute) ? object.public_send(@attribute).to_s : ""
    end

    def native_tag
      @form.select(@attribute, @choices.map { |choice| [ choice[:label], choice[:value] ] }, { prompt: @prompt, selected: current_value.presence },
        id: native_id,
        class: "guest-select__native",
        required: @required,
        disabled: @disabled,
        aria: { describedby: @described_by, invalid: (@invalid ? "true" : nil) }.compact,
        data: @native_data.merge(
          ui__select_menu_target: "native",
          action: [ "change->ui--select-menu#onNativeChange", @native_data[:action] ].compact.join(" ")
        ))
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("guest-select", @class),
        data: data.merge(
          controller: "ui--select-menu",
          ui__select_menu_placeholder_value: @prompt,
          ui__select_menu_fixed_width_value: true,
          # About six options, with the next one cut in half so the guest can
          # see the list scrolls.
          ui__select_menu_max_height_value: 280,
          invalid: @invalid.to_s,
          action: "pointerdown@window->ui--select-menu#onWindowPointerDown"
        )
      )
    end

    # Named by the field's label, then the value: "Bank name, Maybank". A
    # button takes its name from its text, and the text alone is only the
    # value.
    def trigger_attributes
      {
        id: trigger_id,
        type: "button",
        class: "guest-select__trigger",
        disabled: @disabled,
        data: {
          ui__select_menu_target: "trigger",
          action: "click->ui--select-menu#toggle keydown->ui--select-menu#onTriggerKeydown"
        },
        aria: {
          haspopup: "listbox",
          expanded: "false",
          controls: listbox_id,
          labelledby: [ @labelled_by, value_id ].compact.join(" "),
          describedby: @described_by,
          invalid: (@invalid ? "true" : nil)
        }.compact
      }
    end

    def option_attributes(choice, index)
      {
        id: option_id(index),
        role: "option",
        class: "guest-select__option",
        tabindex: "-1",
        data: { ui__select_menu_target: "option", value: choice[:value] },
        aria: { selected: (choice[:value].to_s == current_value).to_s }
      }
    end
  end
end
