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
