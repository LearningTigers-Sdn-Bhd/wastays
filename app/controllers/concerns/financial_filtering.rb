module FinancialFiltering
  extend ActiveSupport::Concern

  included do
    before_action :set_financial_dates
  end

  private

  def set_financial_dates
    @date_preset = params[:date_preset].presence
    @date_preset ||= "custom" if params[:start_date].present? || params[:end_date].present?
    @date_preset ||= "today"

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
      @start_date = parse_filter_date(params[:start_date]) || Date.current.beginning_of_month
      @end_date = parse_filter_date(params[:end_date]) || Date.current.end_of_month
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
end
