# frozen_string_literal: true

module HotelPortal
  class RequestsArchivePresenter
    attr_reader :archive_rows, :archive_counts, :date_window

    def initialize(archive_rows:, archive_counts:, date_window:, view_context:)
      @archive_rows = archive_rows
      @archive_counts = archive_counts
      @date_window = date_window
      @view_context = view_context
    end

    def rows?
      archive_rows.any?
    end

    def window_label
      @view_context.request_window_label(date_window)
    end

    # Where a row opens its detail sheet -- the same sheet the board opens.
    def detail_path(row)
      @view_context.hotel_request_action_show_request_path(
        @view_context.current_hotel,
        kind: row[:kind],
        request_id: row[:request_id]
      )
    end

    def previous_window_path
      @view_context.request_archive_path_for(date_window.previous)
    end

    def next_window_path
      @view_context.request_archive_path_for(date_window.next)
    end

    def today_window_path
      @view_context.request_archive_path_for(date_window.at_today)
    end

    def formatted_requested_at(row)
      helpers.display_housekeeping_datetime(row[:requested_at])
    end

    def formatted_completed_at(row)
      row[:completed_at].present? ? helpers.display_housekeeping_datetime(row[:completed_at]) : "-"
    end

    def show_open_link?(row)
      row[:status] != "cancelled"
    end

    def internal_notes_for(row)
      Array(row[:internal_notes])
    end

    def internal_notes?(row)
      internal_notes_for(row).any?
    end

    def note_body(note)
      note["body"]
    end

    private

    def helpers
      ApplicationController.helpers
    end
  end
end
