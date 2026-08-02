# frozen_string_literal: true

module HotelPortal
  # The housekeeping board's own filter state. Every controller the board hands a
  # task off to has to come back to the board the user was actually looking at,
  # so the keys and the round trip live here rather than in each of them.
  module HousekeepingBoardFilters
    extend ActiveSupport::Concern

    FILTER_KEYS = %i[sort direction].freeze
    ARRAY_FILTER_KEYS = %i[room_type_ids room_statuses assigned_to_ids booking_statuses].freeze

    included do
      helper_method :board_filters
    end

    private

    # The filters as the board itself submitted them.
    def board_filters
      permitted_filter_params(params).to_h.compact_blank
    end

    # Carried through room mutations so the board returns to its current view.
    def returned_filters
      permitted_filter_params(params.fetch(:filters, {})).to_h.compact_blank
    end

    def board_return_path
      hotel_housekeeping_tasks_path(current_hotel, returned_filters)
    end

    def permitted_filter_params(source)
      source.permit(
        *FILTER_KEYS,
        room_type_ids: [],
        room_statuses: [],
        assigned_to_ids: [],
        booking_statuses: []
      )
    end
  end
end
