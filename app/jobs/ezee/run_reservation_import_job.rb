# frozen_string_literal: true

module Ezee
  # Runs an approved reservation import in the background.
  #
  # A property's forward book runs to well over a thousand reservations, each
  # building a financial snapshot and a folio, so this cannot be a request. The
  # ReservationImport row carries the progress, and every step writes to it, so
  # the operator's page stays truthful even if their browser loses the socket.
  #
  # The file is not re-read here. It was resolved into ReservationImportRow at
  # upload, and those rows are what the operator approved on the preview.
  class RunReservationImportJob < ApplicationJob
    queue_as :default

    def perform(reservation_import_id)
      import = ReservationImport.find_by(id: reservation_import_id)
      return if import.nil? || import.finished?

      import.update!(
        status: "running", started_at: Time.current, step: "Starting",
        total_rows: import.rows.importable.count,
        skipped_count: import.rows.where(status: "imported").count
      )
      import.broadcast_progress

      result = ImportReservations.call(import: import, progress: progress_for(import))

      import.update!(
        status: "completed", step: "Done",
        processed_rows: import.total_rows,
        created_count: result.created.size,
        group_count: result.groups.compact.size,
        finished_at: Time.current
      )
      import.broadcast_progress
    rescue StandardError => e
      Rails.logger.error("Reservation import #{reservation_import_id} failed: #{e.message}")
      import&.update(status: "failed", error_message: e.message, finished_at: Time.current)
      import&.broadcast_progress
    end

    private

    def progress_for(import)
      lambda do |step: nil, processed: nil, created: nil, groups: nil, failure: nil|
        import.record_failure!(failure.reservation_number, failure.errors_for_display.last&.dig("message")) if failure
        import.advance!(step: step, processed: processed, created: created, groups: groups)
      end
    end
  end
end
