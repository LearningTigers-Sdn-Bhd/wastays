# frozen_string_literal: true

module ReportDateFiltering
  extend ActiveSupport::Concern

  private

  def parse_report_date_range
    # Handle date_preset parameter (e.g., "2026-05", "this_month", "custom")
    date_preset = params[:date_preset].presence
    date_preset ||= "custom" if params[:start_date].present? || params[:end_date].present?
    date_preset ||= "legacy_date" if params[:date].present?
    date_preset ||= default_report_date_preset
    @date_preset = date_preset

    if date_preset.present?
      case date_preset
      when "today"
        return [ Date.current, Date.current ]
      when "all_time"
        return [ Date.new(2024, 1, 1), Date.current ]
      when "this_year"
        return [ Date.current.beginning_of_year, Date.current.end_of_year ]
      when "last_month"
        last_month = 1.month.ago.to_date
        return [ last_month.beginning_of_month, last_month.end_of_month ]
      when "this_month"
        return [ Date.current.beginning_of_month, Date.current.end_of_month ]
      when "custom"
        start = parse_single_report_date(params[:start_date]) || Date.current.beginning_of_month
        end_date = parse_single_report_date(params[:end_date]) || Date.current.end_of_month
        end_date = start if end_date < start
        return [ start, end_date ]
      when "legacy_date"
        parsed_date = parse_single_report_date(params[:date])
        return [ parsed_date, parsed_date ] if parsed_date
      else
        # Check if it's a specific month (e.g. "2026-03")
        if date_preset =~ /\A\d{4}-\d{2}\z/
          start_date = Date.parse("#{date_preset}-01")
          return [ start_date, start_date.end_of_month ]
        end
      end
    end

    # Backward compatible: if only `date` is provided, treat it as one-day range.
    if params[:start_date].blank? && params[:end_date].blank? && params[:date].present?
      parsed_date = parse_single_report_date(params[:date])
      return [ parsed_date, parsed_date ]
    end

    start_date = parse_single_report_date(params[:start_date])
    end_date = parse_single_report_date(params[:end_date])

    start_date ||= end_date || Date.current
    end_date ||= start_date
    end_date = start_date if end_date < start_date

    [ start_date, end_date ]
  end

  def parse_single_report_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def parse_deposit_liability_date
    date_preset = params[:date_preset].presence
    date_preset ||= "custom" if params[:as_of_date].present?
    date_preset ||= "today"
    @date_preset = date_preset

    if date_preset.present?
      case date_preset
      when "today"
        return Date.current
      when "all_time", "this_year"
        # As of report - use current date for these
        return Date.current
      when "last_month"
        last_month = 1.month.ago.to_date
        return last_month.end_of_month
      when "this_month"
        return Date.current.end_of_month
      when "custom"
        # Use user-provided as_of_date or default to end of month
        return parse_single_report_date(params[:as_of_date]) || Date.current.end_of_month
      else
        # Check if it's a specific month (e.g. "2026-03")
        if date_preset =~ /\A\d{4}-\d{2}\z/
          return Date.parse("#{date_preset}-01").end_of_month
        end
      end
    end

    # Fallback: use as_of_date param or date param or default
    parse_single_report_date(params[:as_of_date]) || parse_single_report_date(params[:date]) || current_hotel.business_date_for || Date.current
  end

  def default_report_date_preset
    "today"
  end

  def parse_date_param(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
