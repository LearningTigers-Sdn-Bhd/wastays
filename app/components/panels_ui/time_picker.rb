# frozen_string_literal: true

module PanelsUI
  # A time picker. The visible field is a themed button (the popover trigger) showing
  # the value; a hidden <input> carries the "HH:MM" value and is the form source of
  # truth. Clicking the field opens a popover holding a segmented HH : MM (24-hour)
  # spinner, which writes the chosen time back.
  #
  # Deliberately not a native <input type="time">: those render the browser's own
  # (unthemable) picker chrome. Time is 24-hour; `format:` is reserved for a future
  # 12-hour variant.
  class TimePicker < PanelsUI::BaseComponent
    SIZES = FormField::SIZES

    def initialize(form:, attribute:, id: nil, labelled_by: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, readonly: false, size: :md,
                   min: nil, max: nil, step: 1, minute_step: nil, second_step: 1,
                   hour_cycle: nil, precision: :minutes, format: :hour24, value: nil, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @value = value
      @id = id
      @labelled_by = labelled_by
      @described_by = described_by
      @invalid = invalid
      @required = required
      @disabled = disabled
      @readonly = readonly
      @size = SIZES.include?(size) ? size : :md
      @min = min
      @max = max
      @minute_step = [ (minute_step || step).to_i, 1 ].max
      @second_step = [ second_step.to_i, 1 ].max
      @format = format
      @hour_cycle = [ 12, 24 ].include?(hour_cycle.to_i) ? hour_cycle.to_i : (format.to_sym == :hour12 ? 12 : 24)
      @precision = precision.to_sym == :seconds ? :seconds : :minutes
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def native_id = @id || @form.field_id(@attribute)
    def stimulus_identifier = "panels-ui--time-picker"
    def root_id = "#{native_id}-time-picker"
    def root_class = "panel-time-picker"
    def popover_id = "#{native_id}-time"
    def popover_root_class = "#{root_id}__popover"
    def anchor_class = "#{root_class}__anchor"
    def placeholder_text = "Select a time"
    def field_disabled? = @disabled || @readonly

    # Hidden field: the "HH:MM" form source of truth the segments write back into.
    def hidden_field
      options = { id: native_id, data: { "#{stimulus_identifier}-target" => "input" } }
      options[:value] = @value unless @value.nil?
      @form.hidden_field(@attribute, **options)
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
            "#{stimulus_identifier}-panels-ui--popover-outlet" => ".#{popover_root_class}",
            "#{stimulus_identifier}-min-value" => serialize_time(@min),
            "#{stimulus_identifier}-max-value" => serialize_time(@max),
            "#{stimulus_identifier}-step-value" => @minute_step,
            "#{stimulus_identifier}-minute-step-value" => @minute_step,
            "#{stimulus_identifier}-second-step-value" => @second_step,
            "#{stimulus_identifier}-hour-cycle-value" => @hour_cycle,
            "#{stimulus_identifier}-precision-value" => @precision,
            size: @size,
            invalid: @invalid.to_s,
            disabled: @disabled.to_s,
            readonly: @readonly.to_s
          }.compact
        )
      )
    end

    private

    # Times may be a Time/DateTime or an "HH:MM" string; strings pass through.
    def serialize_time(value)
      return if value.nil?
      return value if value.is_a?(String)

      pattern = @precision == :seconds ? "%H:%M:%S" : "%H:%M"
      value.respond_to?(:strftime) ? value.strftime(pattern) : value.to_s
    end
  end
end
