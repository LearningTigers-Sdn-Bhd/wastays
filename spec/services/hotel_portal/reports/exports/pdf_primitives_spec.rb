# frozen_string_literal: true

require "rails_helper"
require "pdf-reader"
require "stringio"

# The pieces a document draws with when it drives Prawn itself rather than going through
# PdfReportBuilder. Each is exercised on a bare document so a failure points at the
# primitive rather than at whichever report happens to use it.
RSpec.describe "PDF print primitives" do
  let(:pdf) do
    Prawn::Document.new(page_size: "A4", margin: HotelPortal::Reports::Exports::PdfTheme::PAGE_MARGIN).tap do |document|
      HotelPortal::Reports::Exports::PdfTheme.configure_font(document)
    end
  end

  def extracted_text(content)
    PDF::Reader.new(StringIO.new(content)).pages.map(&:text).join("\n")
  end

  describe HotelPortal::Reports::Exports::PdfPartyBlocks do
    it "draws each block's heading and its labels above their values" do
      described_class.new(pdf: pdf).draw([
        { heading: "Bill to", entries: [ [ "Guest", "Akabane Kiyomi" ], [ "Address", "Minato City, Tokyo" ], [ "Country", "Japan" ] ] },
        { heading: "Invoice details", entries: [ [ "Issued by", "Platform Admin" ], [ "Folio no.", "ACR-26300084/1" ] ] },
        { heading: "Stay details", entries: [ [ "Confirm no.", "AQDWKA" ] ] }
      ])

      text = extracted_text(pdf.render)
      expect(text).to include("BILL TO", "INVOICE DETAILS", "STAY DETAILS")
      expect(text).to include("Guest", "Akabane Kiyomi", "Address", "Minato City, Tokyo", "Country", "Japan")
      expect(text).to include("Issued by", "Platform Admin", "Folio no.", "ACR-26300084/1", "AQDWKA")
    end

    it "drops entries with no value so a missing fact costs a line rather than printing a dash" do
      described_class.new(pdf: pdf).draw([
        { heading: "Bill to", entries: [ [ "Guest", "Akabane Kiyomi" ], [ "Address", nil ], [ "Country", "" ] ] }
      ])

      expect(extracted_text(pdf.render)).not_to include("Address", "Country")
    end

    it "draws a paired entry as two short facts on the same row" do
      described_class.new(pdf: pdf).draw([
        {
          heading: "Stay details",
          entries: [
            [ "Arrival", "01 Sep 2026, 3:00 PM" ],
            { columns: [ [ "Duration", "3 nights" ], [ "Guests", "2 adults" ] ] },
            [ "Booked at", "18 Aug 2026, 12:17 PM" ]
          ]
        }
      ])

      expect(extracted_text(pdf.render)).to include(
        "STAY DETAILS", "Duration", "3 nights", "Guests", "2 adults", "Booked at"
      )
    end

    it "skips a block whose entries are all blank" do
      described_class.new(pdf: pdf).draw([
        { heading: "Bill to", entries: [ [ "Guest", "Akabane Kiyomi" ] ] },
        { heading: "Empty block", entries: [ [ "Nothing", nil ] ] }
      ])

      expect(extracted_text(pdf.render)).not_to include("EMPTY BLOCK")
    end

    # The columns end at different heights by design; the cursor has to clear the tallest
    # of them or the next section draws over a wrapped address.
    it "leaves the cursor below the tallest column" do
      pdf.move_cursor_to 700
      described_class.new(pdf: pdf).draw([
        { heading: "Short", entries: [ [ "Only", "One line" ] ] },
        { heading: "Tall", entries: Array.new(6) { |index| [ "Label #{index}", "Line #{index}" ] } }
      ])

      expect(pdf.cursor).to be < 620
    end
  end

  describe HotelPortal::Reports::Exports::PdfDetailGrid do
    it "draws label above value and wraps past the column count" do
      described_class.new(pdf: pdf).draw(
        [ [ "Account ref", "ACR-26300084" ], [ "Window", "Master" ], [ "Status", "Closed" ],
          [ "Currency", "MYR" ], [ "Fifth", "Wrapped" ] ],
        columns: 4
      )

      text = extracted_text(pdf.render)
      expect(text).to include("ACCOUNT REF", "ACR-26300084", "WINDOW", "Master", "FIFTH", "Wrapped")
    end

    it "drops pairs with a blank value" do
      described_class.new(pdf: pdf).draw([ [ "Status", "Closed" ], [ "Window", nil ] ])

      expect(extracted_text(pdf.render)).not_to include("WINDOW")
    end
  end

  describe HotelPortal::Reports::Exports::PdfNoticeBand do
    it "draws a label and note for each variant" do
      described_class.new(pdf: pdf).draw(label: "VOIDED", note: "No longer evidence of payment.", variant: :danger)
      described_class.new(pdf: pdf).draw(label: "RECONSTRUCTED", note: "Rebuilt from available records.", variant: :warning)

      text = extracted_text(pdf.render)
      expect(text).to include("VOIDED", "No longer evidence of payment.")
      expect(text).to include("RECONSTRUCTED", "Rebuilt from available records.")
    end

    it "draws a label on its own when there is no note" do
      described_class.new(pdf: pdf).draw(label: "DRAFT")

      expect(extracted_text(pdf.render)).to include("DRAFT")
    end
  end

  describe HotelPortal::Reports::Exports::PdfDataTable do
    def draw_table(**overrides)
      described_class.new(pdf: pdf).draw(**{
        section_title: "Transactions", headers: [ "Description", "Amount" ],
        rows: [ [ "Room charge", "350.00" ] ], numeric_columns: [ 1 ], total_row: nil,
        empty_message: "No rows"
      }.merge(overrides))
      extracted_text(pdf.render)
    end

    it "accepts a cell hash that overrides the row's own styling" do
      text = draw_table(rows: [ [ { content: "Room charge\nRate plan: BAR" }, "350.00" ] ])

      expect(text).to include("Room charge", "Rate plan: BAR")
    end

    it "renders a dense table at the smaller size without dropping content" do
      text = draw_table(density: :dense, rows: [ [ "Garden Prestige Suite", "1,350.00" ] ])

      expect(text).to include("Garden Prestige Suite", "1,350.00", "Description", "Amount")
    end

    it "sets a narrower block against the right margin, title included" do
      text = draw_table(section_title: "Summary (MYR)", position: :right, column_widths: [ 120, 80 ])

      expect(text).to include("Summary (MYR)", "Room charge", "350.00")
    end

    it "places optional metadata in the section heading" do
      text = draw_table(section_meta: "45 records")

      expect(text).to include("Transactions", "45 records", "Room charge")
    end

    it "still carries its total when there are no rows" do
      text = draw_table(rows: [], total_row: [ "Total", "0.00" ])

      expect(text).to include("No rows", "Total", "0.00")
    end

    # prawn-table applies cell_style last, so anything a row variant sets has to stay out
    # of cell_style or the variant is silently overridden.
    it "keeps a row variant's own borders and colour" do
      text = draw_table(
        rows: [ [ "Room charge", "350.00" ], [ "Overdue", "120.00" ] ],
        row_variants: { 1 => :alert }
      )

      expect(text).to include("Overdue", "120.00")
    end
  end
end
