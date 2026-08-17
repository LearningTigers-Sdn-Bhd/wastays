# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    module Exports
      # The shared report table: dark header, striped body, optional total, and an empty
      # state that still carries its total. Split out of PdfReportBuilder so a document that
      # drives Prawn itself can wear the same table instead of drawing its own.
      class PdfDataTable
        def initialize(pdf:)
          @pdf = pdf
        end

        # row_variants marks individual data rows as :subtotal, :spacer or :alert, for a
        # summary that groups its lines rather than running flat to a single total.
        def draw(section_title:, headers:, rows:, numeric_columns:, total_row:, empty_message:, column_widths: nil, row_variants: {})
          draw_section_title(section_title)
          return draw_empty_state(empty_message, headers, numeric_columns, total_row, column_widths) if rows.empty?

          table = build(headers, rows, total_row, column_widths, row_variants)
          style_header(table)
          stripe(table, rows, row_variants)
          numeric_columns.each { |index| table.column(index).style(align: :right) }
          style_total(table) if total_row
          table.draw
          @pdf.move_down PdfTheme::SPACE[:lg]
        end

        private

        def draw_section_title(section_title)
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.text section_title, size: PdfTheme::TYPE[:heading], style: :bold
          @pdf.move_down PdfTheme::SPACE[:sm]
        end

        def draw_empty_state(empty_message, headers, numeric_columns, total_row, column_widths)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text empty_message, size: PdfTheme::TYPE[:body], style: :italic
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.move_down PdfTheme::SPACE[:sm]
          draw_total_only(total_row, headers.size, numeric_columns, column_widths) if total_row
          @pdf.move_down PdfTheme::SPACE[:sm]
        end

        def build(headers, rows, total_row, column_widths, row_variants)
          data = [ headers ] + body_cells(rows, row_variants)
          data << total_row if total_row
          # borders and text_color are per cell rather than in cell_style, which prawn-table
          # applies last: a row variant that sets either would otherwise be overridden.
          options = {
            header: true,
            width: column_widths ? column_widths.sum : @pdf.bounds.width,
            cell_style: {
              size: PdfTheme::TYPE[:body], padding: PdfTheme::TABLE_CELL_PADDING,
              border_color: PdfTheme::COLORS[:border], valign: :top
            }
          }
          options[:column_widths] = column_widths if column_widths
          @pdf.make_table(data, **options)
        end

        # Every data cell is built as a hash so a row variant is measured with the weight and
        # height it is drawn at, which row(n).style after the fact cannot promise.
        def body_cells(rows, row_variants)
          rows.each_with_index.map do |row, index|
            variant = variant_style(row_variants[index])
            row.map do |value|
              { content: value.to_s, borders: [ :bottom ], text_color: PdfTheme::COLORS[:ink] }.merge(variant)
            end
          end
        end

        def variant_style(variant)
          case variant
          when :subtotal
            { font_style: :bold, background_color: PdfTheme::COLORS[:primary_light] }
          when :alert
            {
              font_style: :bold, text_color: PdfTheme::COLORS[:warning],
              background_color: PdfTheme::COLORS[:warning_light],
              borders: [ :top, :bottom ], border_color: PdfTheme::COLORS[:warning]
            }
          when :spacer
            # Air between groups, so a grouped summary does not need a table per group.
            { borders: [], height: PdfTheme::SPACE[:md] }
          else {}
          end
        end

        # Restyled after the fact rather than per cell: prawn-table applies cell_style last,
        # so a per-cell text_color here would be overridden into dark-on-dark. Safe for size
        # because the row is measured at the larger body size.
        def style_header(table)
          table.row(0).style(
            background_color: PdfTheme::COLORS[:ink], text_color: PdfTheme::COLORS[:white],
            font_style: :bold, size: PdfTheme::TYPE[:small], borders: []
          )
        end

        # A variant row carries its own background, so striping skips it rather than
        # painting over it.
        def stripe(table, rows, row_variants)
          rows.each_index do |index|
            next unless index.odd? && row_variants[index].nil?

            table.row(index + 1).background_color = PdfTheme::COLORS[:stripe]
          end
        end

        def style_total(table)
          table.row(-1).style(
            background_color: PdfTheme::COLORS[:primary_light], font_style: :bold,
            borders: [ :top ], border_color: PdfTheme::COLORS[:primary]
          )
        end

        def draw_total_only(total_row, column_count, numeric_columns, column_widths)
          data = [ Array.new(column_count).tap { |row| total_row.each_with_index { |value, index| row[index] = value } } ]
          options = {
            width: column_widths ? column_widths.sum : @pdf.bounds.width,
            cell_style: {
              size: PdfTheme::TYPE[:body], padding: PdfTheme::TABLE_CELL_PADDING,
              border_color: PdfTheme::COLORS[:primary], borders: [ :top ],
              text_color: PdfTheme::COLORS[:ink],
              background_color: PdfTheme::COLORS[:primary_light], font_style: :bold
            }
          }
          options[:column_widths] = column_widths if column_widths
          table = @pdf.make_table(data, **options)
          numeric_columns.each { |index| table.column(index).style(align: :right) }
          table.draw
        end
      end
    end
  end
end
