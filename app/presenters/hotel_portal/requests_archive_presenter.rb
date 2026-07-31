# frozen_string_literal: true

module HotelPortal
  class RequestsArchivePresenter
    attr_reader :page, :total_count, :date_window

    def initialize(page:, total_count:, date_window:, view_context:, cursor: nil)
      @page = page
      @total_count = total_count
      @date_window = date_window
      @view_context = view_context
      @cursor = cursor
    end

    def rows
      page.cards
    end

    def rows?
      rows.any?
    end

    # Whether there is more archive behind this page.
    def more?
      page.more?
    end

    # Whether this is a page reached from an earlier one, rather than the newest.
    def paged?
      @cursor.present?
    end

    def next_page_path
      return if page.next_cursor.nil?

      @view_context.request_archive_path_for(date_window, cursor: page.next_cursor.to_param)
    end

    # Back to the newest page, dropping the cursor and keeping the filters.
    def newest_page_path
      @view_context.request_archive_path_for(date_window)
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

    # How a row is dressed. This lived in RequestsArchive, which meant a service
    # deciding what a badge looks like; the classes it hands out are the view's
    # business and the query's is the query.
    def kind_badge_class(row)
      case row[:kind]
      when "housekeeping" then "bg-blue-50 text-blue-600 border-blue-100"
      when "checkout" then "bg-amber-50 text-amber-600 border-amber-100"
      else "bg-rose-50 text-rose-600 border-rose-100"
      end
    end

    def status_badge_class(row)
      case row[:status]
      when "completed", "resolved" then "bg-green-50 text-green-700 border border-green-100"
      when "cancel", "rejected", "cancelled", "failed" then "bg-red-50 text-red-700 border border-red-100"
      when "in_progress" then "bg-blue-50 text-blue-700 border border-blue-100"
      when "pending", "requested" then "bg-yellow-50 text-yellow-700 border border-yellow-100"
      else "bg-muted text-foreground border border-border"
      end
    end

    private

    def helpers
      ApplicationController.helpers
    end
  end
end
