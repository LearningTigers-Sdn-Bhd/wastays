# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      module PdfTheme
        COLORS = {
          ink: "18332F", primary: "205B4E", primary_light: "E7F1ED",
          muted: "667772", border: "D9E4DF", stripe: "F5F8F7", white: "FFFFFF"
        }.freeze
        FONT_FAMILY = "WAStays Unicode"
        # One of the PDF base-14 fonts: never embedded, and every reader can
        # render it. Prawn can only embed a TrueType font as a subset whose
        # character map is Mac Roman, which iOS refuses to read — every glyph
        # comes out as an empty box. Documents that stay inside Windows-1252
        # should use this instead and avoid the problem entirely.
        STANDARD_FONT = "Helvetica"
        FONT_CANDIDATES = [
          {
            normal: "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            bold: "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
          },
          {
            normal: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            bold: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
          }
        ].freeze

        # Readable on every device, but only covers Windows-1252. Callers that
        # may hold text beyond it should rescue Prawn::Errors::IncompatibleStringEncoding
        # and rebuild with configure_font, which reaches the rest of Unicode.
        def self.configure_standard_font(pdf)
          pdf.font(STANDARD_FONT)
        end

        def self.configure_font(pdf)
          paths = font_paths
          pdf.font_families.update(
            FONT_FAMILY => {
              normal: paths.fetch(:normal), bold: paths.fetch(:bold),
              italic: paths.fetch(:normal), bold_italic: paths.fetch(:bold)
            }
          )
          pdf.font(FONT_FAMILY)
        end

        def self.font_paths
          override = ENV["WASTAYS_PDF_UNICODE_FONT_PATH"].presence
          candidates = []
          if override
            candidates << {
              normal: override,
              bold: ENV["WASTAYS_PDF_UNICODE_BOLD_FONT_PATH"].presence || override
            }
          end
          candidates.concat(FONT_CANDIDATES)
          candidates.find { |paths| paths.values.all? { |path| File.file?(path) } } ||
            raise("Unicode PDF font not found. Install fonts-noto-cjk or set WASTAYS_PDF_UNICODE_FONT_PATH.")
        end
      end
    end
  end
end
