# frozen_string_literal: true

require "prawn"
require "prawn/table"

module HotelPortal
  module Reports
    module Exports
      # The shared report table: dark header, striped body, optional total, and an empty
      # state that still carries its total. Split out of PdfReportBuilder so a document that
      # drives Prawn itself can wear the same table instead of drawing its own.
      #
      # Every cell is built as a hash before the table is made, and cell_style carries only
      # what is uniform across the whole table. Both are deliberate: prawn-table applies
      # cell_style *after* per-cell hashes, so anything it sets cannot be overridden per
      # cell, and it measures row heights at build time, so anything set afterwards is drawn
      # at one size and measured at another.
      class PdfDataTable
        def initialize(pdf:)
          @pdf = pdf
        end

        # row_variants marks individual data rows as :subtotal, :spacer or :alert, for a
        # summary that groups its lines rather than running flat to a single total.
        #
        # A row element may be a plain value or a cell hash, which merges over the row's
        # own styling — that is how a cell carries a second line, an alignment, or a colour
        # of its own without the caller restyling the table afterwards.
        #
        # density: :dense steps the whole table down one size for tables carrying more
        # columns than their page comfortably holds. position: :right sets a block narrower
        # than the measure against the right margin, for the summary blocks an invoice ends on.
        def draw(section_title:, headers:, rows:, numeric_columns:, total_row:, empty_message:,
                 column_widths: nil, row_variants: {}, density: :default, position: nil, width: nil,
                 show_header: true)
          sizes = PdfTheme::TABLE_TYPE.fetch(density)
          block_width = resolve_width(width, column_widths)
          if rows.empty?
            break_unless_it_fits(section_title, block_width, position, empty_state_height(empty_message, sizes))
            draw_section_title(section_title, block_width, position)
            return draw_empty_state(empty_message, headers, numeric_columns, total_row, column_widths, block_width, position, sizes)
          end

          table = build(headers, rows, total_row, column_widths, row_variants, sizes, block_width, position, show_header)
          break_unless_it_fits(section_title, block_width, position, kept_height(table, show_header))
          draw_section_title(section_title, block_width, position)
          stripe(table, rows, row_variants, show_header)
          numeric_columns.each { |index| table.column(index).style(align: :right) }
          table.draw
          @pdf.move_down PdfTheme::SPACE[:lg]
        end

        private

        # A section title is drawn after its block is measured, never before: it used to be
        # drawn first, so a block that did not fit left its title alone at the foot of the
        # page with the table it named on the next one.
        #
        # A block only asks for a page of its own if a page can hold it. A table longer than
        # the sheet has to break somewhere, so it asks for its title, its header and its
        # first row — enough that the heading is never the last thing on a page.
        def break_unless_it_fits(section_title, block_width, position, block_height)
          return if @pdf.cursor >= @pdf.bounds.height # already at the top of a page

          needed = title_height(section_title, block_width, position) + block_height
          @pdf.start_new_page if needed > @pdf.cursor
        end

        def kept_height(table, show_header)
          return table.height if table.height <= @pdf.bounds.height

          rows = [ show_header ? 2 : 1, table.row_length ].min
          (0...rows).sum { |index| table.row(index).height }
        end

        def empty_state_height(empty_message, sizes)
          @pdf.height_of(empty_message.to_s.presence || " ", size: sizes[:body]) + PdfTheme::SPACE[:sm]
        end

        def title_height(section_title, block_width, position)
          return 0 if section_title.blank?

          width = position == :right ? block_width : @pdf.bounds.width
          @pdf.height_of(section_title, width: width, **section_title_options) + PdfTheme::SPACE[:sm]
        end

        def section_title_options = { size: PdfTheme::TYPE[:heading], style: :bold }

        def resolve_width(width, column_widths)
          width || column_widths&.sum || @pdf.bounds.width
        end

        # A block set against the right margin takes its title with it, so the title always
        # sits above the block it names rather than at the page's left edge.
        def draw_section_title(section_title, block_width, position)
          return if section_title.blank?

          @pdf.fill_color PdfTheme::COLORS[:ink]
          options = section_title_options
          if position == :right
            height = @pdf.height_of(section_title, width: block_width, **options)
            @pdf.text_box section_title, at: [ @pdf.bounds.width - block_width, @pdf.cursor ],
              width: block_width, height: height, **options
            @pdf.move_down height
          else
            @pdf.text section_title, **options
          end
          @pdf.move_down PdfTheme::SPACE[:sm]
        end

        def draw_empty_state(empty_message, headers, numeric_columns, total_row, column_widths, block_width, position, sizes)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text empty_message, size: sizes[:body], style: :italic
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.move_down PdfTheme::SPACE[:sm]
          draw_total_only(total_row, headers.size, numeric_columns, column_widths, block_width, position, sizes) if total_row
          @pdf.move_down PdfTheme::SPACE[:sm]
        end

        # A block whose columns need no naming — a two-column summary of labels and their
        # amounts — draws no header rather than an empty dark bar where one would go.
        def build(headers, rows, total_row, column_widths, row_variants, sizes, block_width, position, show_header)
          data = body_cells(rows, row_variants, sizes)
          data.unshift(header_cells(headers, sizes)) if show_header
          data << total_cells(total_row, sizes) if total_row
          options = {
            header: show_header, width: block_width,
            # Only what is uniform: prawn-table applies these last, so anything a cell needs
            # to set for itself must not appear here.
            cell_style: { padding: PdfTheme::TABLE_CELL_PADDING, valign: :top }
          }
          options[:column_widths] = column_widths if column_widths
          options[:position] = position if position
          @pdf.make_table(data, **options)
        end

        # Built rather than restyled afterwards, so the header is measured at the size it is
        # drawn at. It used to be restyled, which measured it at the body size.
        def header_cells(headers, sizes)
          headers.map do |header|
            {
              content: header.to_s, size: sizes[:header], font_style: :bold, borders: [],
              background_color: PdfTheme::COLORS[:ink], text_color: PdfTheme::COLORS[:white]
            }
          end
        end

        # Every data cell is built as a hash so a row variant is measured with the weight and
        # height it is drawn at, which row(n).style after the fact cannot promise.
        def body_cells(rows, row_variants, sizes)
          rows.each_with_index.map do |row, index|
            variant = variant_style(row_variants[index])
            row.map { |value| base_cell(sizes[:body]).merge(variant).merge(cell_overrides(value)) }
          end
        end

        def total_cells(total_row, sizes)
          total_row.map do |value|
            base_cell(sizes[:body]).merge(
              font_style: :bold, background_color: PdfTheme::COLORS[:primary_light],
              borders: [ :top ], border_color: PdfTheme::COLORS[:primary]
            ).merge(cell_overrides(value))
          end
        end

        def base_cell(size)
          {
            size: size, borders: [ :bottom ], border_color: PdfTheme::COLORS[:border],
            text_color: PdfTheme::COLORS[:ink]
          }
        end

        # A caller may hand a cell its own hash, which wins over the row's styling.
        def cell_overrides(value)
          value.is_a?(Hash) ? value : { content: value.to_s }
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

        # A variant row carries its own background, so striping skips it rather than
        # painting over it.
        def stripe(table, rows, row_variants, show_header)
          offset = show_header ? 1 : 0
          rows.each_index do |index|
            next unless index.odd? && row_variants[index].nil?

            table.row(index + offset).background_color = PdfTheme::COLORS[:stripe]
          end
        end

        def draw_total_only(total_row, column_count, numeric_columns, column_widths, block_width, position, sizes)
          row = Array.new(column_count)
          total_row.each_with_index { |value, index| row[index] = value }
          options = { width: block_width, cell_style: { padding: PdfTheme::TABLE_CELL_PADDING, valign: :top } }
          options[:column_widths] = column_widths if column_widths
          options[:position] = position if position
          table = @pdf.make_table([ total_cells(row, sizes) ], **options)
          numeric_columns.each { |index| table.column(index).style(align: :right) }
          table.draw
        end
      end
    end
  end
end
