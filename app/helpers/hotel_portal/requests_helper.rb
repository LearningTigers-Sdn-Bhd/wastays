# frozen_string_literal: true

module HotelPortal
  # Moving the requests board's date window has to leave the rest of what the
  # user asked for where it was, so the window travels with the filters rather
  # than instead of them.
  module RequestsHelper
    PRESERVED_FILTER_KEYS = %i[q status kind].freeze

    # Which lanes are shown is many values, not one, so it is permitted as an
    # array. A lazy frame that dropped it would ask for a lane the board is no
    # longer reading.
    PRESERVED_ARRAY_FILTER_KEYS = { lanes: [] }.freeze

    def requests_board_path_for(date_window, extra = {})
      filters = preserved_request_filters.merge(date_window.query_params).merge(extra)
      hotel_requests_path(current_hotel, filters.compact)
    end

    # A lane's count sits inside the control that picks it, where a five-digit
    # number would push the label around. Counts are read, not compared, at that
    # size.
    def abbreviated_count(count)
      return count.to_s if count < 1000

      number_to_human(
        count,
        units: { unit: "", thousand: "k", million: "m", billion: "b" },
        format: "%n%u",
        precision: 2,
        significant: true,
        strip_insignificant_zeros: true
      )
    end

    def request_window_label(date_window)
      first = date_window.start_date
      last = date_window.anchor_date
      format = first.year == last.year ? "%-d %b" : "%-d %b %Y"

      "#{first.strftime(format)} – #{last.strftime('%-d %b %Y')}"
    end

    # The filters a link has to carry so that moving the window, or reading the
    # rest of a column, does not quietly drop what else was asked for.
    def preserved_request_filters
      params.permit(*PRESERVED_FILTER_KEYS, **PRESERVED_ARRAY_FILTER_KEYS)
            .to_h.compact_blank.symbolize_keys
    end
  end
end
