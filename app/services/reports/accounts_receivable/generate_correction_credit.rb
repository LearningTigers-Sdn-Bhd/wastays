# frozen_string_literal: true

module Reports
  module AccountsReceivable
    class GenerateCorrectionCredit
      def initialize(correction:)
        @correction = correction
      end

      def generate
        original = @correction.original_receivable
        builder = HotelPortal::Reports::Exports::PdfReportBuilder.new(
          hotel: @correction.hotel, title: @correction.credit_reference, eyebrow: "Credit note",
          period_label: @correction.completed_at.to_date.to_s, period_label_title: "Issued",
          prepared_by: @correction.closed_by.name, metadata: [], confidential: false
        )
        builder.add_header
        builder.add_party_blocks([
          { heading: "Bill to", entries: [ [ "Company", @correction.original_snapshot.dig("payer", "name") ] ] },
          { heading: "Credit details", entries: [ [ "Issue date", @correction.completed_at.to_date.to_s ], [ "Original invoice", original.formatted_invoice_number ],
            [ "Replacement invoice", @correction.replacement_receivable&.formatted_invoice_number || "None — canceled in full" ] ] }
        ])
        builder.add_table(section_title: "Cancellation of original invoice",
          headers: [ "Description", "Currency", "Credit" ],
          rows: [ [ "Full cancellation of #{original.formatted_invoice_number}", original.currency, HotelPortal::Reports::Exports::PdfTheme.money(original.amount) ] ],
          numeric_columns: [ 2 ], total_row: nil, empty_message: "No correction credit.")
        submission = @correction.e_invoice_submissions.where(status: "valid", document_type: "02").first
        builder.add_note("LHDN UUID: #{submission.uuid}") if submission
        builder.add_note("Reason: #{@correction.reason}")
        builder.add_note("This credit cancels the original receivable. It does not record a cash refund.")
        builder.render
      end
    end
  end
end
