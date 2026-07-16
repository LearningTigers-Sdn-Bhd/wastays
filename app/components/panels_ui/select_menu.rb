# frozen_string_literal: true

module PanelsUI
  # A fully token-styled single-select, built as a progressive enhancement over a
  # real native <select>.
  #
  # The native select (rendered via PanelsUI::NativeSelect) is the source of truth: it
  # carries the form value and is what submits. Server-side and with JS disabled the
  # native control is what the user sees and uses. On connect the
  # `panels-ui--select-menu` Stimulus controller hides the native select and reveals
  # a styled trigger button + a role="listbox" popup that mirror it, syncing every
  # selection back to the native element (so validation, form reset, and submission
  # keep working unchanged).
  #
  #   render PanelsUI::SelectMenu.new(
  #     form: form, attribute: :board,
  #     prompt: "Select a board basis",
  #     choices: [
  #       { label: "Room only", value: "room_only" },
  #       { label: "Breakfast included", value: "bnb" },
  #       { label: "Full board", value: "full", disabled: true }
  #     ]
  #   )
  #
  # Choices accept hashes ({ label:, value:, disabled: }) or plain [label, value]
  # pairs — the same shape as RadioGroup.
  class SelectMenu < PanelsUI::BaseComponent
    SIZES = FormField::SIZES
    PLACEMENTS = %i[bottom bottom_start bottom_end top top_start top_end].freeze

    def initialize(form:, attribute:, choices:, id: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, size: :md, include_blank: false, prompt: nil,
                   selected: nil, placeholder: nil, placement: :bottom_start, offset: 6, class: nil,
                   **attributes)
      raise ArgumentError, "Select menus require choices" if choices.blank?

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
      @placement = PLACEMENTS.include?(placement) ? placement : :bottom_start
      @offset = offset.to_f
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    # The native <select> keeps the plain field id so an external <label for=…>
    # (e.g. FormField's) still associates with the real form control.
    def native_id = @id || @form.field_id(@attribute)
    def root_id = "#{native_id}-select-menu"
    def trigger_id = "#{native_id}-trigger"
    def listbox_id = "#{native_id}-listbox"
    def option_id(index) = "#{native_id}-option-#{index}"

    def floating_placement = @placement.to_s.tr("_", "-")

    def placeholder_text
      @placeholder || @prompt || "Select…"
    end

    # The label shown in the trigger before enhancement JS runs — mirrors what the
    # native select would show so there is no flash of the wrong value.
    def selected_label
      match = normalized_choices.find { |choice| choice[:value].to_s == current_value && !choice[:disabled] }
      match&.fetch(:label)
    end

    def selected_value? = selected_label.present?

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
        class: "panel-select-menu__native",
        data: {
          panels_ui__select_menu_target: "native",
          action: "change->panels-ui--select-menu#onNativeChange"
        }
      )
    end

    def normalized_choices
      @normalized_choices ||= @choices.map do |choice|
        if choice.is_a?(Hash)
          { label: choice[:label], value: choice[:value], disabled: !!choice[:disabled] }
        else
          { label: choice[0], value: choice[1], disabled: false }
        end
      end
    end

    def root_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        id: root_id,
        class: tw_merge("panel-select-menu", @class),
        data: data.merge(
          controller: [ data.delete(:controller), "panels-ui--select-menu" ].compact.join(" "),
          panels_ui__select_menu_placement_value: floating_placement,
          panels_ui__select_menu_offset_value: @offset,
          panels_ui__select_menu_placeholder_value: placeholder_text,
          size: @size,
          invalid: @invalid.to_s,
          disabled: @disabled.to_s,
          action: [ data.delete(:action), "pointerdown@window->panels-ui--select-menu#onWindowPointerDown" ].compact.join(" ")
        )
      )
    end

    def trigger_attributes
      {
        id: trigger_id,
        type: "button",
        class: "panel-select-menu__trigger",
        disabled: @disabled,
        data: {
          panels_ui__select_menu_target: "trigger",
          action: "click->panels-ui--select-menu#toggle keydown->panels-ui--select-menu#onTriggerKeydown"
        },
        aria: {
          haspopup: "listbox",
          expanded: "false",
          controls: listbox_id,
          describedby: @described_by,
          invalid: (@invalid ? "true" : nil)
        }.compact
      }
    end

    def option_attributes(choice, index)
      selected = choice[:value].to_s == current_value && !choice[:disabled]

      {
        id: option_id(index),
        role: "option",
        class: "panel-select-menu__option",
        tabindex: "-1",
        data: {
          panels_ui__select_menu_target: "option",
          value: choice[:value]
        },
        aria: {
          selected: selected.to_s,
          disabled: (choice[:disabled] ? "true" : nil)
        }.compact
      }
    end

    private

    def current_value
      return @selected.to_s if @selected

      object = @form.object
      return "" unless object.respond_to?(@attribute)

      object.public_send(@attribute).to_s
    end
  end
end
