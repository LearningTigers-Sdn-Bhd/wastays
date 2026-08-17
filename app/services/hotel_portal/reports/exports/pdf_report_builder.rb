# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    module Exports
      class PdfReportBuilder
        def initialize(hotel:, title:, period_label:, prepared_by:, period_label_title: "Period", subtitle: nil, eyebrow: nil, generated_at: Time.current, page_layout: :portrait)
          @pdf = Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: PdfTheme::PAGE_MARGIN)
          PdfTheme.configure_font(@pdf)
          @frame = PdfReportFrame.new(
            pdf: @pdf, hotel: hotel, report_name: title, subtitle: subtitle, eyebrow: eyebrow,
            period_label_title: period_label_title, period_label: period_label,
            prepared_by: prepared_by, generated_at: generated_at
          )
        end

        # Lets callers size columns against the usable page width.
        def content_width = @pdf.bounds.width

        # For reports whose sections each deserve their own sheet of paper.
        def start_new_page = @pdf.start_new_page

        def add_header = @frame.draw_header

        def add_summary(metrics) = PdfStatStrip.new(pdf: @pdf).draw(metrics)

        def add_table(section_title:, headers:, rows:, numeric_columns:, total_row:, empty_message:, column_widths: nil)
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.text section_title, size: PdfTheme::TYPE[:heading], style: :bold
          @pdf.move_down PdfTheme::SPACE[:sm]

          if rows.empty?
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.text empty_message, size: PdfTheme::TYPE[:body], style: :italic
            @pdf.fill_color PdfTheme::COLORS[:ink]
            @pdf.move_down PdfTheme::SPACE[:sm]
            draw_total(total_row, headers.size, numeric_columns, column_widths) if total_row
            @pdf.move_down PdfTheme::SPACE[:sm]
            return
          end

          data = [ headers ] + rows
          data << total_row if total_row
          options = {
            header: true,
            width: @pdf.bounds.width,
            cell_style: {
              size: PdfTheme::TYPE[:body], padding: PdfTheme::TABLE_CELL_PADDING,
              border_color: PdfTheme::COLORS[:border], borders: [ :bottom ],
              text_color: PdfTheme::COLORS[:ink], valign: :top
            }
          }
          if column_widths
            options[:column_widths] = column_widths
            options[:width] = column_widths.sum
          end
          table = @pdf.make_table(data, **options)
          # Restyled after the fact rather than per cell: prawn-table applies cell_style
          # last, so a per-cell text_color here would be overridden into dark-on-dark.
          # Safe for size because the row is measured at the larger body size.
          table.row(0).style(
            background_color: PdfTheme::COLORS[:ink], text_color: PdfTheme::COLORS[:white],
            font_style: :bold, size: PdfTheme::TYPE[:small], borders: []
          )
          rows.each_index { |index| table.row(index + 1).background_color = PdfTheme::COLORS[:stripe] if index.odd? }
          numeric_columns.each { |index| table.column(index).style(align: :right) }
          if total_row
            table.row(-1).style(
              background_color: PdfTheme::COLORS[:primary_light], font_style: :bold,
              borders: [ :top ], border_color: PdfTheme::COLORS[:primary]
            )
          end
          table.draw
          @pdf.move_down PdfTheme::SPACE[:lg]
        end

        def render
          @frame.stamp_page_furniture
          @pdf.render
        end

        private

        def draw_total(total_row, column_count, numeric_columns, column_widths)
          data = [ Array.new(column_count).tap { |row| total_row.each_with_index { |value, index| row[index] = value } } ]
          options = {
            width: @pdf.bounds.width,
            cell_style: {
              size: PdfTheme::TYPE[:body], padding: PdfTheme::TABLE_CELL_PADDING,
              border_color: PdfTheme::COLORS[:primary], borders: [ :top ],
              text_color: PdfTheme::COLORS[:ink],
              background_color: PdfTheme::COLORS[:primary_light], font_style: :bold
            }
          }
          if column_widths
            options[:column_widths] = column_widths
            options[:width] = column_widths.sum
          end
          table = @pdf.make_table(data, **options)
          numeric_columns.each { |index| table.column(index).style(align: :right) }
          table.draw
        end
      end
    end
  end
end
