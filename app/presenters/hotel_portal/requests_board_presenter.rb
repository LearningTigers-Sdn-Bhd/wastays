# frozen_string_literal: true

module HotelPortal
  class RequestsBoardPresenter
    attr_reader :board_columns, :board_counts, :current_hotel

    def initialize(board_columns:, board_counts:, current_hotel:, view_context:)
      @board_columns = board_columns
      @board_counts = board_counts
      @current_hotel = current_hotel
      @view_context = view_context
    end

    def columns
      [
        { key: :housekeeping, label: "Housekeeping", accent_class: "border-t-blue-500" },
        { key: :complaint, label: "Complaints", accent_class: "border-t-rose-500" },
        { key: :completed, label: "Recently Completed", accent_class: "border-t-green-500" }
      ]
    end

    def kind_badge_class(card)
      if card[:kind] == "housekeeping"
        "border-blue-100 bg-blue-50 text-blue-700"
      else
        "border-rose-100 bg-rose-50 text-rose-700"
      end
    end

    def target_status(card)
      card[:kind] == "housekeeping" ? "completed" : "resolved"
    end

    def page_params
      @view_context.request.query_parameters.except(:housekeeping_page, :complaint_page, :completed_page, :checkout_page)
    end
  end
end
