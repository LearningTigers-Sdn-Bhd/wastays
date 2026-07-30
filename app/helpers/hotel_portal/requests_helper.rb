# frozen_string_literal: true

module HotelPortal
  # Moving the requests board's date window has to leave the rest of what the
  # user asked for where it was, so the window travels with the filters rather
  # than instead of them.
  module RequestsHelper
    PRESERVED_FILTER_KEYS = %i[q status kind].freeze

    def requests_board_path_for(date_window)
      hotel_requests_path(current_hotel, preserved_request_filters.merge(date_window.query_params))
    end

    def request_archive_path_for(date_window)
      hotel_request_archive_path(current_hotel, preserved_request_filters.merge(date_window.query_params))
    end

    def request_window_label(date_window)
      first = date_window.start_date
      last = date_window.anchor_date
      format = first.year == last.year ? "%-d %b" : "%-d %b %Y"

      "#{first.strftime(format)} – #{last.strftime('%-d %b %Y')}"
    end

    private

    def preserved_request_filters
      params.permit(*PRESERVED_FILTER_KEYS).to_h.compact_blank.symbolize_keys
    end
  end
end
