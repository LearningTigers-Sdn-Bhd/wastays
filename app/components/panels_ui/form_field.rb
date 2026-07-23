# frozen_string_literal: true

module PanelsUI
  # Composes a Rails form control with its label, hint/error message, and optional
  # addons. It deliberately does not render a <form>; use it inside form_with.
  class FormField < PanelsUI::BaseComponent
    SIZES = %i[sm md lg].freeze
    ADDON_ALIGNS = %i[inline_start inline_end block_start block_end].freeze
    ADDON_VARIANTS = %i[bordered bare].freeze
    AUTO_ERROR = Object.new.freeze

    class Addon < PanelsUI::BaseComponent
      attr_reader :align, :variant

      def initialize(align:, variant: :bordered, class: nil, **attributes)
        @align = ADDON_ALIGNS.include?(align) ? align : :inline_end
        @variant = ADDON_VARIANTS.include?(variant) ? variant : :bordered
        @class = binding.local_variable_get(:class)
        @attributes = attributes
      end

      def call
        attributes = @attributes.deep_dup
        data = attributes.delete(:data) || {}

        tag.div(
          content,
          **attributes.merge(
            class: tw_merge("panel-control-group__addon", @class),
            data: data.merge(
              align: @align.to_s.tr("_", "-"),
              variant: @variant
            )
          )
        )
      end
    end

    renders_one :control, types: {
      input: ->(**attributes) { build_input(**attributes) },
      date_picker: ->(**attributes) { build_date_picker(**attributes) },
      time_picker: ->(**attributes) { build_time_picker(**attributes) },
      date_time_picker: ->(**attributes) { build_date_time_picker(**attributes) },
      dropzone: ->(**attributes) { build_dropzone(**attributes) },
      text_area: ->(**attributes) { build_text_area(**attributes) },
      native_select: ->(choices = nil, **attributes) { build_native_select(choices, **attributes) },
      select_menu: ->(choices = nil, **attributes) { build_select_menu(choices, **attributes) },
      combobox: ->(choices = nil, **attributes) { build_combobox(choices, **attributes) },
      autocomplete: ->(**attributes) { build_autocomplete(**attributes) },
      multi_select: ->(choices = nil, **attributes) { build_multi_select(choices, **attributes) }
    }
    renders_many :addons, ->(align:, variant: :bordered, **attributes) {
      Addon.new(align: align, variant: variant, **attributes)
    }

    def initialize(form:, attribute:, label: nil, hint: nil, error: AUTO_ERROR, size: :md,
                   required: false, disabled: false, readonly: false, label_hidden: false,
                   class: nil, **attributes)
      @form = form
      @attribute = attribute
      @label = label
      @hint = hint
      @error = error
      @size = SIZES.include?(size) ? size : :md
      @required = required
      @disabled = disabled
      @readonly = readonly
      @label_hidden = label_hidden
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def with_input(...) = with_control_input(...)
    def with_date_picker(...) = with_control_date_picker(...)
    def with_time_picker(...) = with_control_time_picker(...)
    def with_date_time_picker(...) = with_control_date_time_picker(...)
    def with_dropzone(...) = with_control_dropzone(...)
    def with_text_area(...) = with_control_text_area(...)
    def with_native_select(...) = with_control_native_select(...)
    def with_select_menu(...) = with_control_select_menu(...)
    def with_combobox(...) = with_control_combobox(...)
    def with_autocomplete(...) = with_control_autocomplete(...)
    def with_multi_select(...) = with_control_multi_select(...)

    def control_id
      @form.field_id(@attribute)
    end

    def hint_id = "#{control_id}-hint"
    def error_id = "#{control_id}-error"
    def label_id = "#{control_id}-label"

    def error_message
      return @error unless @error.equal?(AUTO_ERROR)
      return unless @form.object.respond_to?(:errors)

      @form.object.errors[@attribute].first
    end

    def invalid? = error_message.present?
    def hint? = @hint.present? && !invalid?
    def control_group? = addons?
    def control_layout = @control_kind.in?(%i[text_area dropzone]) ? :block : :inline

    def field_attributes
      attributes = @attributes.deep_dup
      data = attributes.delete(:data) || {}

      attributes.merge(
        class: tw_merge("panel-form-field", @class),
        data: data.merge(
          size: @size,
          invalid: invalid?.to_s,
          disabled: @disabled.to_s,
          readonly: @readonly.to_s
        )
      )
    end

    def label_classes
      tw_merge("panel-form-field__label", (@label_hidden ? "sr-only" : nil))
    end

    def description_ids
      [ (hint_id if hint?), (error_id if invalid?) ].compact.join(" ").presence
    end

    def before_render
      raise ArgumentError, "Form fields require a control" unless control?

      return unless control_group?

      raise ArgumentError, "Dropzones do not support addons" if @control_kind == :dropzone

      allowed_aligns = @control_kind == :text_area ? %i[block_start block_end] : %i[inline_start inline_end]
      invalid_aligns = addons.map(&:align) - allowed_aligns
      return if invalid_aligns.empty?

      raise ArgumentError,
            "#{@control_kind == :text_area ? 'Text areas' : 'Inputs'} only support #{allowed_aligns.join(', ')} addons"
    end

    private

    def build_input(**attributes)
      @control_kind = :input
      Input.new(**attributes, **control_options)
    end

    # Cally-backed date control (popover calendar). Renders its own wrapper (like
    # combobox/select_menu), so it does not support addons.
    def build_date_picker(**attributes)
      @control_kind = :date_picker
      DatePicker.new(**attributes, labelled_by: (@label.present? ? label_id : nil), **control_options)
    end

    # Segmented time control (popover HH:MM). Own wrapper, no addons.
    def build_time_picker(**attributes)
      @control_kind = :time_picker
      TimePicker.new(**attributes, labelled_by: (@label.present? ? label_id : nil), **control_options)
    end

    # Cally calendar + segmented time (popover). Own wrapper, no addons.
    def build_date_time_picker(**attributes)
      @control_kind = :date_time_picker
      DateTimePicker.new(**attributes, labelled_by: (@label.present? ? label_id : nil), **control_options)
    end

    def build_dropzone(**attributes)
      @control_kind = :dropzone
      Dropzone.new(
        **attributes,
        labelled_by: (@label.present? ? label_id : nil),
        **control_options.except(:readonly)
      )
    end

    def build_text_area(**attributes)
      @control_kind = :text_area
      TextArea.new(**attributes, **control_options)
    end

    # A native <select> has no readonly state, so drop it rather than emit an
    # attribute the element ignores.
    def build_native_select(choices, **attributes)
      @control_kind = :native_select
      NativeSelect.new(choices: choices, **attributes, **control_options.except(:readonly))
    end

    # Like build_native_select, but the token-styled progressive-enhancement variant. It
    # renders a wrapper rather than a bare control, so it does not support addons —
    # readonly is likewise dropped (a select has no such state).
    def build_select_menu(choices, **attributes)
      @control_kind = :select_menu
      SelectMenu.new(choices: choices, **attributes, **control_options.except(:readonly))
    end

    def build_combobox(choices, **attributes)
      @control_kind = :combobox
      Combobox.new(choices: choices, **attributes, **control_options.except(:readonly))
    end

    def build_autocomplete(**attributes)
      @control_kind = :autocomplete
      Autocomplete.new(**attributes, **control_options)
    end

    def build_multi_select(choices, **attributes)
      @control_kind = :multi_select
      MultiSelect.new(choices: choices, **attributes, **control_options.except(:readonly))
    end

    def control_options
      {
        form: @form,
        attribute: @attribute,
        id: control_id,
        described_by: description_ids,
        invalid: invalid?,
        required: @required,
        disabled: @disabled,
        readonly: @readonly,
        size: @size
      }
    end
  end
end
