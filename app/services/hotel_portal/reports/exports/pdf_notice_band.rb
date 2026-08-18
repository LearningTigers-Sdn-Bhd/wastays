# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # A tinted band carrying a status that has to arrive before the document's own
      # numbers do — a voided receipt reads exactly like a valid one at a glance, and a
      # reconstructed invoice reads exactly like an issued one.
      #
      # Drawn rather than tabled: the label is tracked, and prawn-table cells reject
      # character_spacing.
      class PdfNoticeBand
        VARIANTS = {
          danger: { text: :danger, background: :danger_light },
          warning: { text: :warning, background: :warning_light }
        }.freeze

        PADDING = PdfTheme::SPACE[:sm]

        def initialize(pdf:)
          @pdf = pdf
        end

        def draw(label:, note: nil, variant: :danger)
          colors = VARIANTS.fetch(variant)
          width = @pdf.bounds.width - (PADDING * 2)
          label_options = {
            size: PdfTheme::TYPE[:heading], style: :bold, character_spacing: PdfTheme::LABEL_TRACKING
          }
          note_options = { size: PdfTheme::TYPE[:body] }

          label_height = @pdf.height_of(label, width: width, **label_options)
          note_height = note.present? ? @pdf.height_of(note, width: width, **note_options) : 0
          gap = note.present? ? PdfTheme::SPACE[:xs] : 0
          band_height = label_height + gap + note_height + (PADDING * 2)

          top = @pdf.cursor
          @pdf.fill_color PdfTheme::COLORS[colors[:background]]
          @pdf.fill_rectangle [ 0, top ], @pdf.bounds.width, band_height
          @pdf.fill_color PdfTheme::COLORS[colors[:text]]

          label_top = top - PADDING
          @pdf.text_box label, at: [ PADDING, label_top ], width: width, height: label_height, **label_options
          if note.present?
            @pdf.text_box note, at: [ PADDING, label_top - label_height - gap ],
              width: width, height: note_height, **note_options
          end

          @pdf.move_cursor_to top - band_height
          @pdf.move_down PdfTheme::SPACE[:lg]
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end
      end
    end
  end
end
