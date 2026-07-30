# frozen_string_literal: true

module HotelPortal
  # The housekeeping board's own filter state. Every controller the board hands a
  # task off to has to come back to the board the user was actually looking at,
  # so the keys and the round trip live here rather than in each of them.
  module HousekeepingBoardFilters
    extend ActiveSupport::Concern

    FILTER_KEYS = %i[q date assigned_to room_status].freeze

    included do
      helper_method :board_filters
    end

    private

    # The filters as the board itself submitted them.
    def board_filters
      params.permit(*FILTER_KEYS).to_h.compact_blank
    end

    # Carried through an assignment under their own key, because assigned_to
    # already means "the person being assigned" on that form.
    def returned_filters
      params.fetch(:filters, {}).permit(*FILTER_KEYS).to_h.compact_blank
    end

    def board_return_path
      hotel_housekeeping_tasks_path(current_hotel, returned_filters)
    end
  end
end
