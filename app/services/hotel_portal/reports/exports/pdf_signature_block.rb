# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # Places to sign, side by side: a rule to sign above with its label beneath, and
      # clear air above the rule to sign into.
      #
      # Deliberately not a bordered box. The invoice drew one and it read as another data
      # table — a box puts a second horizontal beside the one you actually sign on, and the
      # reader has to work out which is which. The system's whole border vocabulary is one
      # hairline at RULE_WIDTH, and a signing area does not need a fourth.
      #
      # Drawn rather than tabled: the label is tracked, and prawn-table cells reject
      # character_spacing.
      class PdfSignatureBlock
        GUTTER = PdfTheme::SPACE[:xl]
        # Room to actually sign. Two steps of the grid rather than one: a signature is
        # written by hand and needs more than a line of type's worth of height.
        SIGNING_SPACE = PdfTheme::SPACE[:xl] * 2
        LABEL_GAP = PdfTheme::SPACE[:xs]
        CAPTION_GAP = PdfTheme::SPACE[:xs]
        # A captured signature is set to a fixed height so two of them side by side sit on
        # the same rule whatever their source images measure.
        IMAGE_HEIGHT = 40
        IMAGE_GAP = PdfTheme::SPACE[:xs]

        def initialize(pdf:)
          @pdf = pdf
        end

        # fields: [{ label:, image: nil, caption: nil }, ...]
        #
        # image: a captured signature drawn above the rule, for a document that already
        # holds one; without it the space is left blank to sign by hand. caption: a muted
        # line under the label, for who signed and when.
        #
        # position: :right sets a block narrower than the measure against the right margin,
        # the same way PdfDataTable does.
        def draw(fields:, position: nil, width: nil)
          fields = Array(fields).reject { |field| field[:label].blank? }
          return if fields.empty?

          block_width = width || @pdf.bounds.width
          left_offset = position == :right ? @pdf.bounds.width - block_width : 0
          column_width = column_width_for(fields.size, block_width)

          # Measured before anything is drawn, so a block that cannot fit moves whole
          # rather than leaving its rules at the foot of one page and its labels on the next.
          @pdf.start_new_page if @pdf.cursor < height_of(fields) + PdfTheme::SPACE[:lg]
          @pdf.move_down SIGNING_SPACE

          top = @pdf.cursor
          bottoms = fields.each_with_index.map do |field, index|
            draw_field(field, at: left_offset + (index * (column_width + GUTTER)), width: column_width, top: top)
          end

          @pdf.move_cursor_to bottoms.min
          @pdf.move_down PdfTheme::SPACE[:lg]
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        private

        # Draws one column and reports the y it ended at, so the caller can clear the
        # tallest of them.
        def draw_field(field, at:, width:, top:)
          draw_image(field[:image], at: at, top: top) if field[:image]

          @pdf.stroke_color PdfTheme::COLORS[:border]
          @pdf.line_width PdfTheme::RULE_WIDTH
          @pdf.stroke_horizontal_line at, at + width, at: top

          cursor = top - LABEL_GAP
          cursor -= draw_label(field[:label], at: at, width: width, top: cursor)
          return cursor if field[:caption].blank?

          cursor -= CAPTION_GAP
          cursor - draw_caption(field[:caption], at: at, width: width, top: cursor)
        end

        # Sat on the rule rather than above it by its own height, so a tall source image
        # cannot push the signature off the line it belongs to.
        def draw_image(image, at:, top:)
          @pdf.image image, at: [ at, top + IMAGE_HEIGHT + IMAGE_GAP ], height: IMAGE_HEIGHT
        rescue Prawn::Errors::UnsupportedImageType
          nil
        end

        def draw_label(label, at:, width:, top:)
          text = label.to_s.upcase
          options = label_options
          height = @pdf.height_of(text, width: width, **options)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text_box text, at: [ at, top ], width: width, height: height, **options
          height
        end

        def draw_caption(caption, at:, width:, top:)
          text = caption.to_s
          options = caption_options
          height = @pdf.height_of(text, width: width, **options)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text_box text, at: [ at, top ], width: width, height: height, **options
          height
        end

        # The signing space plus the tallest column's labels, which is what the page-break
        # guard has to clear.
        def height_of(fields)
          tallest = fields.map do |field|
            height = LABEL_GAP + @pdf.height_of(field[:label].to_s.upcase, **label_options)
            next height if field[:caption].blank?

            height + CAPTION_GAP + @pdf.height_of(field[:caption].to_s, **caption_options)
          end.max
          SIGNING_SPACE + tallest
        end

        def column_width_for(count, block_width)
          (block_width - (GUTTER * (count - 1))) / count.to_f
        end

        def label_options
          {
            size: PdfTheme::TYPE[:micro], style: :bold,
            character_spacing: PdfTheme::LABEL_TRACKING
          }
        end

        def caption_options = { size: PdfTheme::TYPE[:micro] }
      end
    end
  end
end
