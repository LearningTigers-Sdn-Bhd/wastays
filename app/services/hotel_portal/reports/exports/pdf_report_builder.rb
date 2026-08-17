# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    module Exports
      class PdfReportBuilder
        def initialize(hotel:, title:, period_label:, prepared_by:, period_label_title: "Period", subtitle: nil, eyebrow: nil, generated_at: Time.current, page_layout: :portrait, confidential: true)
          @pdf = Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: PdfTheme::PAGE_MARGIN)
          PdfTheme.configure_font(@pdf)
          @frame = PdfReportFrame.new(
            pdf: @pdf, hotel: hotel, report_name: title, subtitle: subtitle, eyebrow: eyebrow,
            period_label_title: period_label_title, period_label: period_label,
            prepared_by: prepared_by, generated_at: generated_at, confidential: confidential
          )
        end

        # Lets callers size columns against the usable page width.
        def content_width = @pdf.bounds.width

        # For reports whose sections each deserve their own sheet of paper.
        def start_new_page = @pdf.start_new_page

        def add_header = @frame.draw_header

        def add_summary(metrics) = PdfStatStrip.new(pdf: @pdf).draw(metrics)

        # Sections keep their keyword interface; the table itself lives in PdfDataTable so a
        # document that drives Prawn directly can draw the same one.
        def add_table(...) = PdfDataTable.new(pdf: @pdf).draw(...)

        def render
          @frame.stamp_page_furniture
          @pdf.render
        end
      end
    end
  end
end
