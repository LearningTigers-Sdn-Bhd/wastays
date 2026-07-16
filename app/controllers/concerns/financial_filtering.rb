module FinancialFiltering
  extend ActiveSupport::Concern

  included do
    before_action :set_financial_dates
  end

  private

  def set_financial_dates
    @date_preset = params[:date_preset].presence
    @date_preset ||= "custom" if params[:date_range].present? || params[:start_date].present? || params[:end_date].present?
    @date_preset ||= "today"

    # Export links include resolved dates so relative presets remain stable if
    # the request crosses a day or month boundary.
    explicit_start = parse_filter_date(params[:start_date])
    explicit_end = parse_filter_date(params[:end_date])
    if explicit_start || explicit_end
      @start_date = explicit_start || explicit_end
      @end_date = explicit_end || @start_date
      @end_date = @start_date if @end_date < @start_date
      return
    end

    case @date_preset
    when "today"
      @start_date = Date.current
      @end_date = Date.current
    when "all_time"
      @start_date = Date.new(2024, 1, 1) # System start
      @end_date = Date.current
    when "this_year"
      @start_date = Date.current.beginning_of_year
      @end_date = Date.current.end_of_year
    when "last_month"
      @start_date = 1.month.ago.to_date.beginning_of_month
      @end_date = 1.month.ago.to_date.end_of_month
    when "this_month"
      @start_date = Date.current.beginning_of_month
      @end_date = Date.current.end_of_month
    when "custom"
      range_start, range_end = parse_filter_date_range(params[:date_range])
      @start_date = range_start || parse_filter_date(params[:start_date]) || Date.current.beginning_of_month
      @end_date = range_end || parse_filter_date(params[:end_date]) || Date.current.end_of_month
      @end_date = @start_date if @end_date < @start_date
    else
      # Check if it's a specific month (e.g. "2026-03")
      if @date_preset =~ /\A\d{4}-\d{2}\z/
        @start_date = Date.parse("#{@date_preset}-01")
        @end_date = @start_date.end_of_month
      else
        @start_date = Date.current
        @end_date = Date.current
      end
    end
  end

  def apply_search(scope, query, fields)
    return scope if query.blank?

    conditions = fields.map { |field| "#{field} ILIKE :q" }.join(" OR ")
    scope.where(conditions, q: "%#{query}%")
  end

  def parse_filter_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_filter_date_range(value)
    endpoints = value.to_s.split("/", -1)
    return [ nil, nil ] unless endpoints.length == 2

    dates = endpoints.map { |endpoint| Date.iso8601(endpoint) }
    dates.all? ? dates : [ nil, nil ]
  rescue ArgumentError, TypeError
    [ nil, nil ]
  end
end
