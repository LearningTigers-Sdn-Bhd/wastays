# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # A tinted pill carrying one word about the document it sits on. Where PdfNoticeBand
      # takes the full measure for a status that has to arrive before the numbers do, a
      # badge sits inline beside something else and answers a question the reader has
      # already asked — is this bill closed.
      #
      # It measures before it draws, so a caller can set a title against it and know how
      # much of the measure is left. Drawn rather than tabled: the label is tracked, and
      # prawn-table cells reject character_spacing.
      class PdfBadge
        VARIANTS = {
          positive: { text: :primary, background: :primary_light },
          warning: { text: :warning, background: :warning_light },
          danger: { text: :danger, background: :danger_light },
          neutral: { text: :muted, background: :stripe }
        }.freeze

        PADDING_X = PdfTheme::SPACE[:sm]
        PADDING_Y = PdfTheme::SPACE[:xs]
        CORNER_RADIUS = PdfTheme::SPACE[:xs]

        def initialize(pdf:)
          @pdf = pdf
        end

        def width(label) = label_width(label) + (PADDING_X * 2)

        def height = label_height + (PADDING_Y * 2)

        # Drawn from its top-left corner in the document's own coordinates, so a caller
        # that has measured a row can place it without the cursor moving under it.
        def draw(label:, at:, variant: :neutral)
          colors = VARIANTS.fetch(variant.to_sym)
          text = display_label(label)
          left, top = at

          @pdf.fill_color PdfTheme::COLORS[colors[:background]]
          @pdf.fill_rounded_rectangle [ left, top ], width(label), height, CORNER_RADIUS

          @pdf.fill_color PdfTheme::COLORS[colors[:text]]
          @pdf.text_box text, at: [ left + PADDING_X, top - PADDING_Y ],
            width: label_width(label), height: label_height, **label_options

          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        private

        # Upper case with tracking is the print label tier, the same treatment the eyebrow
        # and the metadata labels take at this size.
        def display_label(label) = label.to_s.upcase

        def label_options
          { size: PdfTheme::TYPE[:micro], style: :bold, character_spacing: PdfTheme::LABEL_TRACKING }
        end

        # width_of does not account for the tracking between the glyphs, so the label pays
        # for its own spacing or the pill closes on its last letter.
        def label_width(label)
          text = display_label(label)
          @pdf.width_of(text, size: PdfTheme::TYPE[:micro], style: :bold) +
            (PdfTheme::LABEL_TRACKING * text.length)
        end

        def label_height = @pdf.height_of("X", **label_options)
      end
    end
  end
end
