# frozen_string_literal: true

module HotelPortal
  class RequestsArchivePresenter
    attr_reader :archive_rows, :archive_counts

    def initialize(archive_rows:, archive_counts:)
      @archive_rows = archive_rows
      @archive_counts = archive_counts
    end

    def rows?
      archive_rows.any?
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
