# frozen_string_literal: true

module PanelsUI
  # A datetime picker. The visible field is a themed button (the popover trigger) showing
  # the value; a hidden <input> carries the "YYYY-MM-DDTHH:MM" value and is the form
  # source of truth. Clicking the field opens a popover holding a Cally <calendar-date>
  # above a segmented HH : MM (24-hour) spinner; the controller combines the chosen date
  # and time and writes them back.
  #
  # Deliberately not a native <input type="datetime-local">: those render the browser's
  # own (unthemable, doubled) picker chrome. Single value only (no range). The popover is
  # the nested PanelsUI::Popover, so the calendar lives in this component's themed subtree.
  class DateTimePicker < PanelsUI::BaseComponent
    SIZES = FormField::SIZES
    CAPTION_LAYOUTS = DatePicker::CAPTION_LAYOUTS

    def initialize(form:, attribute:, range: false, linked_to: nil, id: nil, labelled_by: nil, described_by: nil, invalid: false,
                   required: false, disabled: false, readonly: false, size: :md,
                   min: nil, max: nil, step: 1, minute_step: nil, second_step: 1,
                   hour_cycle: nil, precision: :minutes, format: :hour24,
                   value: nil, months: 1, responsive_months: true,
                   caption_layout: :label, year_range: nil, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @value = value
      @range = range
      @linked_to = linked_to
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
      @hour_cycle = [ 12, 24 ].include?(hour_cycle.to_i) ? hour_cycle.to_i : (format.to_sym == :hour12 ? 12 : 24)
      @precision = precision.to_sym == :seconds ? :seconds : :minutes
      @months = [ 1, 2 ].include?(months.to_i) ? months.to_i : 1
      @responsive_months = ActiveModel::Type::Boolean.new.cast(responsive_months)
      @caption_layout = CAPTION_LAYOUTS.include?(caption_layout.to_sym) ? caption_layout.to_sym : :label
      @year_range = normalize_year_range(year_range)
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def native_id = @id || @form.field_id(@attribute)
    def stimulus_identifier = "panels-ui--date-time-picker"
    def root_id = "#{native_id}-date-time-picker"
    def root_class = "panel-date-time-picker"
    def popover_id = "#{native_id}-datetime"
    def popover_root_class = "#{root_id}__popover"
    def anchor_class = "#{root_class}__anchor"
    def single_input_range? = @range && @linked_to.nil?
    def mode = single_input_range? ? "range" : "single"
    def calendar_element = single_input_range? ? "calendar-range" : "calendar-date"
    def placeholder_text = single_input_range? ? "Select date & time range" : "Select date & time"
    def field_disabled? = @disabled || @readonly
    def dropdown_caption? = @caption_layout == :dropdown
    def calendar_months = single_input_range? ? @months : 1
    def render_second_month? = calendar_months == 2
    def month_choices = Date::MONTHNAMES.each_with_index.filter_map { |name, index| [ name, index ] if index.positive? }
    def year_choices = @year_range.to_a
    def linked_to_id = @linked_to && @form.field_id(@linked_to)
    def main_panel_id = "#{popover_id}-panel"
    def time_popover_id(scope = nil) = "#{native_id}-#{scope || 'time'}-columns"

    # Hidden field: the "YYYY-MM-DDTHH:MM" form source of truth.
    def hidden_field
      options = { id: native_id, data: { "#{stimulus_identifier}-target" => "input" } }
      options[:value] = @value unless @value.nil?
      @form.hidden_field(@attribute, **options)
    end

    # Cally bounds are date-only; the picker keeps the full datetime bound in the
    # data-values consumed by the controller.
    def calendar_min = date_part(@min)
    def calendar_max = date_part(@max)

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
            "#{stimulus_identifier}-mode-value" => mode,
            "#{stimulus_identifier}-min-value" => serialize_bound(@min),
            "#{stimulus_identifier}-max-value" => serialize_bound(@max),
            "#{stimulus_identifier}-step-value" => @minute_step,
            "#{stimulus_identifier}-minute-step-value" => @minute_step,
            "#{stimulus_identifier}-second-step-value" => @second_step,
            "#{stimulus_identifier}-hour-cycle-value" => @hour_cycle,
            "#{stimulus_identifier}-precision-value" => @precision,
            "#{stimulus_identifier}-linked-to-value" => linked_to_id,
            "#{stimulus_identifier}-months-value" => calendar_months,
            "#{stimulus_identifier}-responsive-months-value" => @responsive_months,
            size: @size,
            invalid: @invalid.to_s,
            disabled: @disabled.to_s,
            readonly: @readonly.to_s
          }.compact
        )
      )
    end

    private

    # ISO datetime-local: "YYYY-MM-DDTHH:MM". Accepts Time/DateTime or a string.
    def serialize_bound(value)
      return if value.nil?
      return value if value.is_a?(String)

      pattern = @precision == :seconds ? "%Y-%m-%dT%H:%M:%S" : "%Y-%m-%dT%H:%M"
      value.respond_to?(:strftime) ? value.strftime(pattern) : value.to_s
    end

    def date_part(value)
      serialized = serialize_bound(value)
      serialized && serialized.split("T").first
    end

    def normalize_year_range(value)
      range = value || ((Date.current.year - 100)..(Date.current.year + 10))
      range.is_a?(Range) ? range : Range.new(*Array(range).minmax)
    end
  end
end
