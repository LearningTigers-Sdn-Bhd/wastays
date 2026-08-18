# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # The print sibling of the on-screen MetricStrip: label above value, columns
      # separated by hairlines rather than filled. A tint was tried and withdrawn for the
      # same reason PdfReportFrame dropped it from the metadata strip — a fill behind
      # short values reads as an empty table header.
      #
      # Drawn rather than tabled on purpose. prawn-table cells reject character_spacing,
      # and it measures row heights when the table is built, so a size set afterwards is
      # drawn but not measured. Measuring each box here sidesteps both.
      class PdfStatStrip
        MAX_COLUMNS = 4
        # A column narrower than this wraps a seven-figure money value at TYPE[:stat], and
        # §12 forbids shrinking scale-critical text to fit. So the grid answers to the page:
        # four columns need a landscape sheet, portrait takes three.
        MIN_COLUMN_WIDTH = 160
        # A single metric stretched across the full measure reads as a mistake, so a lone
        # column keeps one third of the page and lets the rest of the line stay empty.
        LONE_COLUMN_DIVISOR = 3
        # Half falls either side of a divider, so the rule sits midway between the text it
        # separates.
        GUTTER = PdfTheme::SPACE[:md]
        BLOCK_PADDING = PdfTheme::SPACE[:sm]
        LABEL_VALUE_GAP = PdfTheme::SPACE[:xs]

        def initialize(pdf:)
          @pdf = pdf
        end

        # metrics: [[label, value], ...] — the same shape PdfReportBuilder#add_summary
        # has always taken.
        def draw(metrics)
          pairs = Array(metrics).reject { |(label, value)| label.blank? && value.blank? }
          return if pairs.empty?

          rows = balanced_rows(pairs)
          widths = column_widths(rows.first.size)
          offsets = widths.each_with_index.map { |_, index| widths[0...index].sum }

          start_new_page_unless_it_fits(rows, widths)
          @pdf.stroke_color PdfTheme::COLORS[:border]
          @pdf.line_width PdfTheme::RULE_WIDTH

          rows.each_with_index do |row, index|
            draw_rule_between_rows unless index.zero?
            draw_row(row, widths, offsets)
          end
          @pdf.move_down PdfTheme::SPACE[:lg]
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        private

        def draw_row(row, widths, offsets)
          row_top = @pdf.cursor
          content_top = row_top - BLOCK_PADDING

          label_height = draw_cells(
            row.map { |(label, _)| label.to_s.upcase }, widths, offsets, content_top,
            size: PdfTheme::TYPE[:micro], color: PdfTheme::COLORS[:muted],
            character_spacing: PdfTheme::LABEL_TRACKING
          )
          value_height = draw_cells(
            row.map { |(_, value)| value.to_s }, widths, offsets, content_top - label_height - LABEL_VALUE_GAP,
            size: PdfTheme::TYPE[:stat], color: PdfTheme::COLORS[:ink]
          )

          row_bottom = content_top - label_height - LABEL_VALUE_GAP - value_height - BLOCK_PADDING
          draw_dividers(offsets, row.size, from: row_top, to: row_bottom)
          @pdf.move_cursor_to row_bottom
        end

        # Draws one tier of a row and reports the height of its tallest column, so the
        # tier below starts clear of a label or value that wrapped.
        def draw_cells(texts, widths, offsets, top, size:, color:, character_spacing: 0)
          @pdf.fill_color color
          heights = texts.each_with_index.map do |text, index|
            options = { size: size, style: :bold, character_spacing: character_spacing }
            width = text_width(widths, index)
            height = @pdf.height_of(text.presence || " ", width: width, **options)
            @pdf.text_box text, at: [ text_left(offsets, index), top ], width: width, height: height, **options
            height
          end
          heights.max
        end

        def draw_dividers(offsets, filled_columns, from:, to:)
          (1...filled_columns).each { |index| @pdf.stroke_vertical_line from, to, at: offsets[index] }
        end

        def draw_rule_between_rows
          @pdf.stroke_horizontal_rule
        end

        # Wrapped rows sit on the widest row's grid so their dividers line up, which is why
        # the split is balanced rather than filled to MAX_COLUMNS first: five metrics are
        # 3 + 2, never 4 + 1.
        def balanced_rows(pairs)
          row_count = (pairs.size / max_columns.to_f).ceil
          pairs.each_slice((pairs.size / row_count.to_f).ceil).to_a
        end

        def max_columns = (@pdf.bounds.width / MIN_COLUMN_WIDTH).floor.clamp(1, MAX_COLUMNS)

        def column_widths(columns)
          usable = @pdf.bounds.width
          divisor = columns == 1 ? LONE_COLUMN_DIVISOR : columns
          widths = Array.new(columns, (usable / divisor).floor)
          # The last column absorbs the rounding remainder so a full strip ends flush with
          # the right margin. A lone column keeps its third and does not stretch.
          widths[-1] += usable - widths.sum if columns == divisor
          widths
        end

        def text_left(offsets, index) = offsets[index] + (index.zero? ? 0 : GUTTER)

        # The first column stays flush to the page margin, so only its trailing gutter
        # comes off the measure.
        def text_width(widths, index) = widths[index] - GUTTER - (index.zero? ? 0 : GUTTER)

        def start_new_page_unless_it_fits(rows, widths)
          return if @pdf.cursor >= @pdf.bounds.height # already at the top of a page

          @pdf.start_new_page if measured_height(rows, widths) > @pdf.cursor
        end

        # Every row carries its own padding top and bottom, so a rule between two rows
        # already has a full step of air either side and adds no height of its own.
        def measured_height(rows, widths) = rows.sum { |row| row_height(row, widths) }

        def row_height(row, widths)
          label_height = tier_height(row.map { |(label, _)| label.to_s.upcase }, widths, PdfTheme::TYPE[:micro], PdfTheme::LABEL_TRACKING)
          value_height = tier_height(row.map { |(_, value)| value.to_s }, widths, PdfTheme::TYPE[:stat], 0)
          BLOCK_PADDING + label_height + LABEL_VALUE_GAP + value_height + BLOCK_PADDING
        end

        def tier_height(texts, widths, size, character_spacing)
          texts.each_with_index.map do |text, index|
            @pdf.height_of(
              text.presence || " ", width: text_width(widths, index),
              size: size, style: :bold, character_spacing: character_spacing
            )
          end.max
        end
      end
    end
  end
end
