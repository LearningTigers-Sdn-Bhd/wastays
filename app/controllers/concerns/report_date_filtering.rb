# frozen_string_literal: true

module ReportDateFiltering
  extend ActiveSupport::Concern

  private

  def parse_report_date_range
    parser = HotelPortal::Reports::DateRangeParser.new(params, current_hotel)
    dates = parser.parse_range
    @date_preset = parser.date_preset
    dates
  end

  def parse_deposit_liability_date
    parser = HotelPortal::Reports::DateRangeParser.new(params, current_hotel)
    date = parser.parse_as_of_date
    @date_preset = parser.date_preset
    date
  end

  def parse_date_param(value)
    HotelPortal::Reports::DateRangeParser.parse_date(value)
  end

  def parse_date_range(start_val, end_val)
    [ HotelPortal::Reports::DateRangeParser.parse_date(start_val), HotelPortal::Reports::DateRangeParser.parse_date(end_val) ]
  end
end
