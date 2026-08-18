# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # Label above value, in columns, wrapping to as many rows as the pairs need. The
      # same tier the frame's metadata strip uses, without its bounding rules, so a
      # document can carry a second band of facts under the one the frame already drew.
      #
      # Use this where the facts really are label-and-short-value pairs. A block that
      # carries a name and an address wants PdfPartyBlocks instead.
      class PdfDetailGrid
        GUTTER = PdfTheme::SPACE[:xl]
        LABEL_GAP = PdfTheme::SPACE[:xs]
        ROW_GAP = PdfTheme::SPACE[:md]
        DEFAULT_COLUMNS = 4

        def initialize(pdf:)
          @pdf = pdf
        end

        # pairs: [[label, value], ...]. Blank values drop out, so a missing fact costs a
        # column rather than printing a dash.
        def draw(pairs, columns: DEFAULT_COLUMNS)
          pairs = Array(pairs).reject { |(label, value)| label.blank? || value.blank? }
          return if pairs.empty?

          widths = column_widths(columns)
          offsets = widths.each_with_index.map { |_, index| widths[0...index].sum }

          pairs.each_slice(columns).with_index do |row, index|
            @pdf.move_down ROW_GAP unless index.zero?
            draw_row(row, widths, offsets)
          end
          @pdf.move_down PdfTheme::SPACE[:lg]
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        private

        def draw_row(row, widths, offsets)
          top = @pdf.cursor
          label_height = draw_tier(
            row.map { |(label, _)| label.to_s.upcase }, widths, offsets, top,
            size: PdfTheme::TYPE[:micro], style: :bold, color: PdfTheme::COLORS[:muted],
            character_spacing: PdfTheme::LABEL_TRACKING
          )
          value_top = top - label_height - LABEL_GAP
          value_height = draw_tier(
            row.map { |(_, value)| value.to_s }, widths, offsets, value_top,
            size: PdfTheme::TYPE[:small], style: :normal, color: PdfTheme::COLORS[:ink]
          )
          @pdf.move_cursor_to value_top - value_height
        end

        # Draws one tier and reports the height of its tallest column, so the tier below
        # starts clear of a label or value that wrapped.
        def draw_tier(texts, widths, offsets, top, size:, style:, color:, character_spacing: 0)
          @pdf.fill_color color
          options = { size: size, style: style, character_spacing: character_spacing }
          heights = texts.each_with_index.map do |text, index|
            width = widths[index] - GUTTER
            height = @pdf.height_of(text, width: width, **options)
            @pdf.text_box text, at: [ offsets[index], top ], width: width, height: height, **options
            height
          end
          heights.max
        end

        def column_widths(count)
          width = @pdf.bounds.width
          widths = Array.new(count, (width / count).floor)
          widths[-1] += width - widths.sum
          widths
        end
      end
    end
  end
end
