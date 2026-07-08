# frozen_string_literal: true

module HotelPortal::ArrivalsHelper
  def arrivals_header_date(date)
    date.strftime("%d %b %Y")
  end
end
