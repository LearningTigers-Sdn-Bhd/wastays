# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    module Exports
      class PdfReportBuilder
        def initialize(hotel:, title:, period_label:, prepared_by:, period_label_title: "Period", subtitle: nil, generated_at: Time.current, page_layout: :portrait)
          @pdf = Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: [ 40, 32, 42, 32 ])
          PdfTheme.configure_font(@pdf)
          @frame = PdfReportFrame.new(
            pdf: @pdf, hotel: hotel, report_name: title, subtitle: subtitle,
            period_label_title: period_label_title, period_label: period_label,
            prepared_by: prepared_by, generated_at: generated_at
          )
        end

        # Lets callers size columns against the usable page width.
        def content_width = @pdf.bounds.width

        # For reports whose sections each deserve their own sheet of paper.
        def start_new_page = @pdf.start_new_page

        def add_header = @frame.draw_header

        def add_summary(metrics)
          return if metrics.empty?

          table = @pdf.make_table(
            metrics,
            width: @pdf.bounds.width,
            cell_style: { padding: [ 7, 9 ], border_color: PdfTheme::COLORS[:border], borders: [ :bottom ] }
          )
          table.column(0).style(
            background_color: PdfTheme::COLORS[:primary_light], text_color: PdfTheme::COLORS[:muted],
            size: 8, font_style: :bold
          )
          table.column(1).style(text_color: PdfTheme::COLORS[:ink], size: 11, font_style: :bold, align: :right)
          table.draw
          @pdf.move_down 16
        end

        def add_table(section_title:, headers:, rows:, numeric_columns:, total_row:, empty_message:, column_widths: nil)
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.text section_title, size: 11, style: :bold
          @pdf.move_down 6

          if rows.empty?
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.text empty_message, size: 9, style: :italic
            @pdf.fill_color PdfTheme::COLORS[:ink]
            @pdf.move_down 10
            draw_total(total_row, headers.size, numeric_columns, column_widths) if total_row
            @pdf.move_down 6
            return
          end

          data = [ headers ] + rows
          data << total_row if total_row
          options = {
            header: true,
            width: @pdf.bounds.width,
            cell_style: {
              size: 8.5, padding: [ 5, 6 ], border_color: PdfTheme::COLORS[:border],
              borders: [ :bottom ], text_color: PdfTheme::COLORS[:ink], valign: :top
            }
          }
          if column_widths
            options[:column_widths] = column_widths
            options[:width] = column_widths.sum
          end
          table = @pdf.make_table(data, **options)
          table.row(0).style(
            background_color: PdfTheme::COLORS[:ink], text_color: PdfTheme::COLORS[:white],
            font_style: :bold, size: 8, borders: []
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
          @pdf.move_down 16
        end

        def render
          @frame.stamp_footer
          @pdf.render
        end

        private

        def draw_total(total_row, column_count, numeric_columns, column_widths)
          data = [ Array.new(column_count).tap { |row| total_row.each_with_index { |value, index| row[index] = value } } ]
          options = {
            width: @pdf.bounds.width,
            cell_style: {
              size: 8.5, padding: [ 5, 6 ], border_color: PdfTheme::COLORS[:primary],
              borders: [ :top ], text_color: PdfTheme::COLORS[:ink],
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
