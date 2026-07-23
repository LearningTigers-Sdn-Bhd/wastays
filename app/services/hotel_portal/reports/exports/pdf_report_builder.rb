# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    module Exports
      class PdfReportBuilder
        def initialize(hotel:, title:, period_label:, subtitle: nil, generated_at: Time.current, page_layout: :portrait)
          @hotel = hotel
          @title = title
          @subtitle = subtitle
          @period_label = period_label
          @generated_at = generated_at
          @pdf = Prawn::Document.new(page_size: "A4", page_layout: page_layout, margin: [ 40, 32, 42, 32 ])
          PdfTheme.configure_font(@pdf)
        end

        def add_header
          top = @pdf.cursor
          @pdf.fill_color PdfTheme::COLORS[:primary]
          @pdf.fill_rectangle([ 0, top ], @pdf.bounds.width, 58)
          @pdf.fill_color PdfTheme::COLORS[:white]
          @pdf.text_box @title.upcase, at: [ 16, top - 14 ], width: @pdf.bounds.width - 32, height: 20, size: 16, style: :bold
          if @subtitle.present?
            @pdf.text_box @subtitle, at: [ 16, top - 36 ], width: @pdf.bounds.width - 32, height: 16, size: 9
          end
          logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
          @pdf.image logo_path, at: [ @pdf.bounds.right - 145, top - 10 ], width: 125 if File.exist?(logo_path)
          @pdf.move_down 70
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.text @hotel.name.to_s, size: 12, style: :bold
          @pdf.move_down 2
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text "Reporting period: #{@period_label}", size: 9
          @pdf.text "Generated: #{@generated_at.strftime('%d %b %Y, %H:%M %Z')}", size: 8
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.move_down 14
        end

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
        end

        def render
          @pdf.number_pages(
            "Page <page> of <total>",
            at: [ 0, -8 ], width: @pdf.bounds.width, align: :center, size: 8,
            color: PdfTheme::COLORS[:muted]
          )
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
