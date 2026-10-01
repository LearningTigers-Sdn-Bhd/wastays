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

    # `layout` forces a report layout; left nil, the file is detected.
    def initialize(import:, layout: nil)
      @import = import
      @layout = layout
    end

    def call
      parsed = parse
      return Result.new(rows_written: 0, error: parsed.error) unless parsed.success?

      plan = ImportPlan.call(hotel: @import.hotel, rows: parsed.rows)
      write!(plan)

      @import.update!(total_rows: plan.importable.size, source_layout: parsed.layout&.to_s)
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
        booking_status: entry.booking_status,
        source_key: row.source_key,
        internal_note: row.internal_note,
        boat_in_type: row.boat_in&.dig(:type),
        boat_in_time: row.boat_in&.dig(:time),
        boat_out_type: row.boat_out&.dig(:type),
        boat_out_time: row.boat_out&.dig(:time),
        rate_plan_id: entry.rate_plan&.id,
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
        ParseFile.call(path: tempfile.path, filename: blob.filename.to_s, layout: @layout)
      end
    end
  end
end
