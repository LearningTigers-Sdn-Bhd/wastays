# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      # Running text on a document that is otherwise made of tables — policies, requests,
      # disclosures, closing instructions. Not a table and not a notice band: it carries no
      # tint and no border, and it wraps to as many lines as it needs.
      #
      # A prose block is measured before it is drawn and moved to the next page whole. A
      # heading stranded at the foot of a page above the paragraph it introduces is the one
      # failure this exists to prevent.
      class PdfProseBlock
        def initialize(pdf:)
          @pdf = pdf
        end

        # Body copy under an optional section heading.
        def draw(text, heading: nil, trailing: PdfTheme::SPACE[:lg])
          return if text.blank?

          ensure_fits(text, size: PdfTheme::TYPE[:body], heading: heading)
          @pdf.fill_color PdfTheme::COLORS[:ink]
          if heading.present?
            @pdf.text heading, size: PdfTheme::TYPE[:heading], style: :bold
            @pdf.move_down PdfTheme::SPACE[:sm]
          end
          @pdf.text text, size: PdfTheme::TYPE[:body], leading: 2
          @pdf.move_down trailing
        end

        # The quiet tier: disclosures and notes that qualify what is above them without
        # competing with it.
        def draw_muted(text, trailing: PdfTheme::SPACE[:lg])
          return if text.blank?

          ensure_fits(text, size: PdfTheme::TYPE[:micro], heading: nil)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text text, size: PdfTheme::TYPE[:micro], leading: 2
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.move_down trailing
        end

        # A closing instruction, set apart from the body by weight rather than by a rule.
        def draw_closing(text, trailing: 0)
          return if text.blank?

          ensure_fits(text, size: PdfTheme::TYPE[:small], heading: nil)
          @pdf.fill_color PdfTheme::COLORS[:muted]
          @pdf.text text, size: PdfTheme::TYPE[:small], style: :italic
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.move_down trailing if trailing.positive?
        end

        private

        def ensure_fits(text, size:, heading:)
          height = @pdf.height_of(text, size: size, leading: 2)
          if heading.present?
            height += @pdf.height_of(heading, size: PdfTheme::TYPE[:heading], style: :bold) + PdfTheme::SPACE[:sm]
          end
          @pdf.start_new_page if @pdf.cursor < height + PdfTheme::SPACE[:lg]
        end
      end
    end
  end
end
