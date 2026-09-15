# frozen_string_literal: true

module Ezee
  # Reads an uploaded export, resolves it against the property, and writes the
  # result down.
  #
  # This runs once, at upload. Everything after it -- the preview, its filters,
  # its paging, and the commit itself -- reads these rows instead of the
  # spreadsheet, so a thousand-row file is parsed once rather than on every
  # page view, and the bookings created are the ones the operator approved.
  class BuildImportRows
    Result = Struct.new(:rows_written, :error, keyword_init: true) do
      def success? = error.blank?
    end

    def self.call(...) = new(...).call

    def initialize(import:)
      @import = import
    end

    def call
      parsed = parse
      return Result.new(rows_written: 0, error: parsed.error) unless parsed.success?

      plan = ImportPlan.call(hotel: @import.hotel, rows: parsed.rows)
      write!(plan)

      @import.update!(total_rows: plan.importable.size)
      Result.new(rows_written: plan.entries.size)
    end

    private

    # One insert for the whole file rather than a save per reservation.
    def write!(plan)
      records = plan.entries.map { |entry| attributes_for(entry) }

      ReservationImportRow.transaction do
        @import.rows.delete_all
        records.each_slice(500) { |slice| ReservationImportRow.insert_all!(slice) }
      end
    end

    def attributes_for(entry)
      row = entry.row
      now = Time.current
      {
        reservation_import_id: @import.id,
        sheet_row: row.sheet_row,
        reservation_number: row.reservation_number,
        status: entry.status.to_s,
        guest_name: row.guest_name,
        source: row.source,
        room_number: row.room_number,
        room_type_name: row.room_type,
        rate_type: row.rate_type,
        booked_at: row.booked_at,
        booked_by: row.user,
        arrival: row.arrival,
        departure: row.departure,
        adults: row.adults,
        children: row.children,
        nights: row.nights,
        total_amount: row.total_amount,
        amount_paid: row.amount_paid,
        remark: row.remark,
        issues: entry.issues,
        agency_name: entry.agency_name,
        # The inferred multi-room block, flattened to something a row can carry
        # and a query can group on.
        group_key: entry.group_key && entry.group_key.join(" | "),
        room_type_id: entry.room_type&.id,
        room_id: entry.room&.id,
        booking_id: entry.existing_booking_id,
        created_at: now,
        updated_at: now
      }
    end

    # Roo needs a path with a meaningful extension, and the attachment is only a
    # key in storage, so it is written out under its original name.
    def parse
      blob = @import.file.blob
      Tempfile.create([ "ezee", File.extname(blob.filename.to_s) ], binmode: true) do |tempfile|
        tempfile.write(blob.download)
        tempfile.flush
        ReservationListParser.call(path: tempfile.path, filename: blob.filename.to_s)
      end
    end
  end
end
