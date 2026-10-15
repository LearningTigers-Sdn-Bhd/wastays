# frozen_string_literal: true

module Reports
  module Bookings
    # The cancellation tiers and their notes, as the voucher and the booking summary print
    # them. Takes a Cancellations::PolicySummary.
    class CancellationPolicySection
      def initialize(pdf:)
        @pdf = pdf
      end

      def draw(cancellation)
        return if cancellation.blank?

        draw_table(cancellation.rows) if cancellation.rows.any?
        draw_notes(cancellation)
      end

      private

      def draw_table(rows)
        HotelPortal::Reports::Exports::PdfDataTable.new(pdf: @pdf).draw(
          section_title: "Cancellation policy",
          headers: [ "If cancelled", "Charge" ],
          rows: rows.map { |row| [ row.window, row.charge ] },
          numeric_columns: [],
          total_row: nil,
          empty_message: "No cancellation tiers are configured.",
          column_widths: [ 0.62, 0.38 ].map { |fraction| @pdf.bounds.width * fraction }
        )
      end

      def draw_notes(cancellation)
        notes = [
          cancellation.refund_note,
          cancellation.description,
          cancellation.structured? ? nil : cancellation.legacy_text
        ].compact_blank
        return if notes.empty?

        HotelPortal::Reports::Exports::PdfProseBlock.new(pdf: @pdf).draw_muted(notes.map { |note| "- #{note}" }.join("\n"))
      end
    end
  end
end
