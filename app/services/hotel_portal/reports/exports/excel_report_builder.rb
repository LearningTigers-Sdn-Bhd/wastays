# frozen_string_literal: true

require "caxlsx"

module HotelPortal
  module Reports
    module Exports
      class ExcelReportBuilder
        MAX_ROW_HEIGHT = 409
        MIN_ROW_HEIGHT = 24

        def initialize(hotel:, title:, period_label:, generated_at: Time.current)
          @hotel = hotel
          @title = title
          @period_label = period_label
          @generated_at = generated_at
          @sheet_widths = {}
        end

        def generate
          package = Axlsx::Package.new
          package.use_shared_strings = true
          @workbook = package.workbook
          @theme = ExcelTheme.new(@workbook)
          yield self
          package.to_stream.read
        end

        def add_sheet(name:, widths:, orientation: nil)
          sheet = @workbook.add_worksheet(name: unique_sheet_name(name))
          sheet.column_widths(*widths)
          sheet.sheet_view.zoom_scale = 100
          sheet.page_setup.orientation = orientation || (widths.size > 6 ? :landscape : :portrait)
          sheet.page_setup.fit_to_width = 1
          sheet.page_setup.fit_to_height = 0
          @sheet_widths[sheet.object_id] = widths
          sheet
        end

        def add_header(sheet:, subtitle: nil)
          last_column = column_letter(column_count(sheet))
          title = [ @title, subtitle.presence ].compact.join(" - ")

          add_merged_row(sheet, title, @theme.fetch(:title), last_column, height: 34)
          add_merged_row(sheet, @hotel.name.to_s, @theme.fetch(:metadata), last_column, height: 20)
          add_merged_row(sheet, "Reporting period: #{@period_label}", @theme.fetch(:metadata), last_column, height: 20)
          add_merged_row(
            sheet,
            "Generated: #{@generated_at.strftime('%d %b %Y, %H:%M %Z')}",
            @theme.fetch(:metadata),
            last_column,
            height: 20
          )
        end

        def add_summary(sheet:, metrics:, title: "Summary")
          last_column = column_letter(column_count(sheet))
          add_merged_row(sheet, title, @theme.fetch(:section), last_column, height: 24)
          sheet.add_row([ "Metric", "Value", "Currency" ], style: Array.new(3, @theme.fetch(:header)), height: 26)

          metrics.each do |label, value, currency|
            value_style = value.is_a?(Integer) ? @theme.fetch(:kpi_integer) : @theme.fetch(:kpi_money)
            sheet.add_row(
              [ label, value, currency ],
              style: [ @theme.fetch(:kpi_label), value_style, @theme.fetch(:currency) ],
              height: 28
            )
          end
        end

        def add_note(sheet:, text:)
          last_column = column_letter(column_count(sheet))
          add_merged_row(sheet, text, @theme.fetch(:metadata), last_column, height: merged_row_height(sheet, text))
        end

        def add_table(sheet:, section_title:, headers:, rows:, column_types:, total_row:, empty_message:)
          validate_table!(headers, column_types)
          last_column = column_letter(headers.size)
          add_merged_row(sheet, section_title, @theme.fetch(:section), last_column, height: 24)

          header_row = sheet.rows.size + 1
          sheet.add_row(headers, style: Array.new(headers.size, @theme.fetch(:header)), height: 28)

          if rows.any?
            rows.each_with_index do |values, index|
              sheet.add_row(
                values,
                style: row_styles(column_types, index),
                types: cell_types(column_types, values),
                height: row_height(sheet, values)
              )
            end
          else
            sheet.add_row([ empty_message ], style: [ @theme.fetch(:empty) ], height: MIN_ROW_HEIGHT)
            sheet.merge_cells("A#{sheet.rows.size}:#{last_column}#{sheet.rows.size}")
          end

          if total_row
            sheet.add_row(
              total_row,
              style: total_styles(column_types),
              types: cell_types(column_types, total_row, label_first: true),
              height: MIN_ROW_HEIGHT
            )
          end

          last_data_row = header_row + [ rows.size, 1 ].max
          sheet.auto_filter = "A#{header_row}:#{last_column}#{last_data_row}"
          freeze_below(sheet, header_row)
        end

        private

        def add_merged_row(sheet, value, style, last_column, height:)
          sheet.add_row([ value ], style: [ style ], height: height)
          sheet.merge_cells("A#{sheet.rows.size}:#{last_column}#{sheet.rows.size}")
        end

        def row_styles(column_types, row_index)
          suffix = row_index.odd? ? "_alt" : ""
          column_types.map do |type|
            style = %i[text].include?(type) ? "body#{suffix}" : "#{type}#{suffix}"
            @theme.fetch(style.to_sym)
          end
        end

        def total_styles(column_types)
          column_types.map.with_index do |type, index|
            index.zero? || type == :text ? @theme.fetch(:total_label) : @theme.fetch("total_#{type}".to_sym)
          end
        end

        def cell_types(column_types, values, label_first: false)
          column_types.map.with_index do |type, index|
            next :string if (label_first && index.zero?) || values[index].nil?

            {
              text: :string,
              date: :date,
              datetime: :time,
              integer: :integer,
              percentage: :float,
              money: :float
            }.fetch(type)
          end
        end

        def row_height(sheet, values)
          widths = @sheet_widths.fetch(sheet.object_id)
          lines = values.each_with_index.map do |value, index|
            width = [ widths.fetch(index, 12).to_f, 1 ].max
            value.to_s.lines(chomp: true).sum { |line| [ (line.scan(/\X/).size / width).ceil, 1 ].max }
          end.max || 1
          [ [ lines * 15, MIN_ROW_HEIGHT ].max, MAX_ROW_HEIGHT ].min
        end

        def merged_row_height(sheet, value)
          width = @sheet_widths.fetch(sheet.object_id).sum.to_f
          lines = value.to_s.lines(chomp: true).sum { |line| [ (line.scan(/\X/).size / width).ceil, 1 ].max }
          [ [ lines * 15, MIN_ROW_HEIGHT ].max, MAX_ROW_HEIGHT ].min
        end

        def freeze_below(sheet, header_row)
          sheet.sheet_view.pane do |pane|
            pane.state = :frozen
            pane.y_split = header_row
            pane.top_left_cell = "A#{header_row + 1}"
            pane.active_pane = :bottom_left
          end
        end

        def validate_table!(headers, column_types)
          return if headers.size == column_types.size

          raise ArgumentError, "headers and column_types must have the same size"
        end

        def column_count(sheet)
          @sheet_widths.fetch(sheet.object_id).size
        end

        def unique_sheet_name(name)
          base = name.to_s.gsub(/[\[\]:*?\\\/]/, " ").squish.first(31).presence || "Report"
          existing = @workbook.worksheets.map(&:name)
          return base unless existing.include?(base)

          suffix = 2
          loop do
            candidate = "#{base.first(28)} #{suffix}"
            return candidate unless existing.include?(candidate)

            suffix += 1
          end
        end

        def column_letter(column_count)
          number = column_count
          letters = +""
          while number.positive?
            number, remainder = (number - 1).divmod(26)
            letters.prepend((65 + remainder).chr)
          end
          letters
        end
      end
    end
  end
end
