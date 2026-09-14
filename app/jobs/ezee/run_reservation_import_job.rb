# frozen_string_literal: true

module Ezee
  # Runs an approved reservation import in the background.
  #
  # A property's forward book runs to well over a thousand reservations, each
  # building a financial snapshot and a folio, so this cannot be a request. The
  # ReservationImport row carries the progress, and every step writes to it, so
  # the operator's page stays truthful even if their browser loses the socket.
  class RunReservationImportJob < ApplicationJob
    queue_as :default

    def perform(reservation_import_id)
      import = ReservationImport.find_by(id: reservation_import_id)
      return if import.nil? || import.finished?

      import.update!(status: "running", started_at: Time.current, step: "Reading the file")
      import.broadcast_progress

      parsed = parse(import)
      raise parsed.error if parsed.error.present?

      import.update!(total_rows: parsed.rows.size, step: "Checking against the property")
      import.broadcast_progress

      plan = ImportPlan.call(hotel: import.hotel, rows: parsed.rows)
      import.update!(
        total_rows: plan.importable.size,
        skipped_count: plan.entries.count { |entry| entry.status == :imported }
      )

      result = ImportReservations.call(
        hotel: import.hotel, plan: plan, user: import.user,
        progress: progress_for(import)
      )

      import.update!(
        status: "completed", step: "Done",
        processed_rows: plan.importable.size,
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
        import.record_failure!(failure.row.reservation_number, failure.error) if failure
        import.advance!(step: step, processed: processed, created: created, groups: groups)
      end
    end

    # Roo needs a path with a meaningful extension, and the attachment is only a
    # key in storage, so it is written out under its original name.
    def parse(import)
      blob = import.file.blob
      Tempfile.create([ "ezee", File.extname(blob.filename.to_s) ], binmode: true) do |tempfile|
        tempfile.write(blob.download)
        tempfile.flush
        ReservationListParser.call(path: tempfile.path, filename: blob.filename.to_s)
      end
    end
  end
end
