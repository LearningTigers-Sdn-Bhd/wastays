# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # The parties to a document, side by side: who it bills, who issued it, what it
      # covers. An invoice is not a form, so this is not a table — the blocks are separated
      # by white space rather than by borders, and each one runs as many lines as its
      # content needs.
      #
      # This is the exception to the metadata strip. The strip holds one short value per
      # label on a single line; a party block holds a name and an address, and the columns
      # end at different heights. Documents wearing this pass `metadata: []` to the frame,
      # so the page carries one of the two and never both.
      #
      # Drawn rather than tabled for the reasons §12 records: headings are tracked, and
      # prawn-table measures its rows when the table is built.
      class PdfPartyBlocks
        GUTTER = PdfTheme::SPACE[:xl]
        HEADING_GAP = PdfTheme::SPACE[:sm]
        ENTRY_GAP = PdfTheme::SPACE[:xs]
        # Wide enough for "Confirmation no." at TYPE[:small] without wrapping, which is the
        # longest label these documents use.
        LABEL_FRACTION = 0.42

        def initialize(pdf:)
          @pdf = pdf
        end

        # blocks: [{ heading:, entries: [[label_or_nil, value], ...] }, ...]
        # An entry with no label spans the block's full width, which is how an address
        # reads as an address rather than as a column of unlabelled values.
        def draw(blocks)
          # A heading with nothing under it is worse than no column at all.
          blocks = Array(blocks).reject { |block| entries(block).empty? }
          return if blocks.empty?

          widths = column_widths(blocks.size)
          offsets = widths.each_with_index.map { |_, index| widths[0...index].sum }
          top = @pdf.cursor

          bottoms = blocks.each_with_index.map do |block, index|
            draw_block(block, at: offsets[index], width: widths[index] - GUTTER, top: top)
          end

          @pdf.move_cursor_to bottoms.min
          @pdf.move_down PdfTheme::SPACE[:xl]
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        private

        # Draws one column and reports the y it ended at, so the caller can clear the
        # tallest of them.
        def draw_block(block, at:, width:, top:)
          block_entries = entries(block)
          stacked = stacked?(block_entries, width)
          cursor = draw_heading(block[:heading], at: at, width: width, top: top)
          block_entries.each do |label, value|
            cursor = draw_entry(label, value, at: at, width: width, top: cursor, stacked: stacked) - ENTRY_GAP
          end
          cursor
        end

        # Stacking is decided for the whole column, not per entry: one stacked line among
        # inline ones reads as a mistake rather than as a fit.
        def stacked?(block_entries, width)
          value_width = width - (width * LABEL_FRACTION).floor
          block_entries.any? { |label, value| label.present? && wraps?(value, value_width) }
        end

        def draw_heading(heading, at:, width:, top:)
          return top if heading.blank?

          options = heading_options
          text = heading.to_s.upcase
          height = @pdf.height_of(text, width: width, **options)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text_box text, at: [ at, top ], width: width, height: height, **options
          top - height - HEADING_GAP
        end

        # A label sits beside its value while every value in the column fits the space that
        # leaves. When one does not, the whole column stacks: a date broken across two lines
        # mid-value reads worse than a label on a line of its own.
        def draw_entry(label, value, at:, width:, top:, stacked:)
          return draw_value(value, at: at, width: width, top: top) if label.blank?
          return draw_stacked_entry(label, value, at: at, width: width, top: top) if stacked

          label_width = (width * LABEL_FRACTION).floor
          value_width = width - label_width
          label_bottom = draw_label(label, at: at, width: label_width, top: top)
          value_bottom = draw_value(value, at: at + label_width, width: value_width, top: top)
          # A wrapped value must not be overwritten by the next entry's label.
          [ label_bottom, value_bottom ].min
        end

        def draw_stacked_entry(label, value, at:, width:, top:)
          label_bottom = draw_label(label, at: at, width: width, top: top)
          draw_value(value, at: at, width: width, top: label_bottom)
        end

        def wraps?(value, width) = @pdf.width_of(value.to_s, **value_options) > width

        def draw_label(label, at:, width:, top:)
          options = value_options
          height = @pdf.height_of(label.to_s, width: width, **options)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text_box label.to_s, at: [ at, top ], width: width, height: height, **options
          top - height
        end

        def draw_value(value, at:, width:, top:)
          options = value_options
          height = @pdf.height_of(value.to_s, width: width, **options)
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.text_box value.to_s, at: [ at, top ], width: width, height: height, **options
          top - height
        end

        def entries(block)
          Array(block[:entries]).filter_map do |entry|
            label, value = entry
            next if value.blank?

            [ label, value ]
          end
        end

        def heading_options
          {
            size: PdfTheme::TYPE[:micro], style: :bold,
            character_spacing: PdfTheme::LABEL_TRACKING
          }
        end

        def value_options = { size: PdfTheme::TYPE[:small], leading: 1 }

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
