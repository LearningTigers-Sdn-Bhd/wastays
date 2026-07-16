# frozen_string_literal: true

module PanelsUI
  # A date picker. The visible field is a themed button (the popover trigger) showing
  # the formatted value; a hidden <input> carries the ISO value and is the form source
  # of truth. Clicking the field opens a popover holding a Cally calendar
  # (<calendar-date> / <calendar-range>), which writes the chosen ISO date back.
  #
  # Deliberately not a native <input type="date">: those render the browser's own
  # (unthemable, doubled) picker chrome. Here the popover is the only picker.
  #
  # The popover is the nested PanelsUI::Popover component, so the calendar lives inside
  # this component's themed DOM subtree — tokens resolve from the nearest [data-theme]
  # ancestor and no calendar is portalled to <body>. Styling is done via Cally's
  # Shadow-DOM ::part() hooks (see panel/date-picker.css).
  #
  # range: false                   -> single value
  #        true                    -> single-input range ("start to end")
  #        true + linked_to: :attr -> this is the START field of a linked two-field
  #                                   range; the END field is a separate DatePicker,
  #                                   wired by dom id (start change raises the end min).
  #
  # Time and datetime are separate components (PanelsUI::TimePicker / DateTimePicker).
  class DatePicker < PanelsUI::BaseComponent
    SIZES = FormField::SIZES
    CAPTION_LAYOUTS = %i[label dropdown].freeze

    def initialize(form:, attribute:, range: false, linked_to: nil, id: nil, labelled_by: nil,
                   described_by: nil, invalid: false, required: false, disabled: false,
                   readonly: false, size: :md, min: nil, max: nil, date_format: nil,
                   placeholder: nil, value: nil, months: 1, responsive_months: true,
                   caption_layout: :label, year_range: nil, class: nil, **attributes)
      @form = form
      @attribute = attribute
      @range = range
      @linked_to = linked_to
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
      @date_format = date_format
      @placeholder = placeholder
      @months = [ 1, 2 ].include?(months.to_i) ? months.to_i : 1
      @responsive_months = ActiveModel::Type::Boolean.new.cast(responsive_months)
      @caption_layout = CAPTION_LAYOUTS.include?(caption_layout.to_sym) ? caption_layout.to_sym : :label
      @year_range = normalize_year_range(year_range)
      @class = binding.local_variable_get(:class)
      @attributes = attributes
    end

    def native_id = @id || @form.field_id(@attribute)
    def stimulus_identifier = "panels-ui--date-picker"
    def root_id = "#{native_id}-date-picker"
    def root_class = "panel-date-picker"
    def popover_id = "#{native_id}-calendar"
    def popover_root_class = "#{root_id}__popover"
    def anchor_class = "#{root_class}__anchor"

    def single_input_range? = @range && @linked_to.nil?
    def mode = single_input_range? ? "range" : "single"
    def calendar_element = single_input_range? ? "calendar-range" : "calendar-date"
    def placeholder_text = @placeholder || (single_input_range? ? "Select a range" : "Select a date")
    def field_disabled? = @disabled || @readonly
    def dropdown_caption? = @caption_layout == :dropdown
    def calendar_months = single_input_range? ? @months : 1
    def render_second_month? = calendar_months == 2
    def month_choices = Date::MONTHNAMES.each_with_index.filter_map { |name, index| [ name, index ] if index.positive? }
    def year_choices = @year_range.to_a

    def linked_to_id
      return if @linked_to.nil?

      @form.field_id(@linked_to)
    end

    # Hidden field: the ISO form source of truth the calendar writes back into.
    # `value:` seeds an initial value (single "YYYY-MM-DD", range "start/end").
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
            # The nested Popover controller this one drives (close on selection).
            "#{stimulus_identifier}-panels-ui--popover-outlet" => ".#{popover_root_class}",
            "#{stimulus_identifier}-mode-value" => mode,
            # Opt-in overrides; omitted via compact so the controller falls back to
            # sensible per-type defaults.
            "#{stimulus_identifier}-date-format-value" => @date_format,
            "#{stimulus_identifier}-min-value" => serialize_bound(@min),
            "#{stimulus_identifier}-max-value" => serialize_bound(@max),
            # DOM id of the END field when this is the start of a linked range.
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

    # Bounds may be a Date/Time/DateTime or a preformatted string. Cally parses
    # ISO-8601 dates (YYYY-MM-DD); strings pass through untouched.
    def serialize_bound(value)
      return if value.nil?
      return value if value.is_a?(String)

      value.respond_to?(:to_date) ? value.to_date.iso8601 : value.to_s
    end

    def normalize_year_range(value)
      range = value || ((Date.current.year - 100)..(Date.current.year + 10))
      range.is_a?(Range) ? range : Range.new(*Array(range).minmax)
    end
  end
end
