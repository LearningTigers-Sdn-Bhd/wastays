# frozen_string_literal: true

module HotelPortal
  module Reports
    module Exports
      module PdfTheme
        # Semantic pairs are deliberately desaturated so they read as siblings of the
        # green rather than as a second palette dropped on top of it.
        COLORS = {
          ink: "18332F", primary: "205B4E", primary_light: "E7F1ED",
          muted: "667772", border: "D9E4DF", stripe: "F5F8F7", white: "FFFFFF",
          danger: "8C2F2A", danger_light: "FBECEA",
          warning: "8A5A16", warning_light: "FBF3E4"
        }.freeze

        # One step per role. Sizes are fixed, never shrunk to fit, so the same role is
        # the same size on every report regardless of how long its content is.
        TYPE = {
          display: 20,  # report title, set in DISPLAY_FAMILY
          subhead: 12,  # hotel name
          heading: 11,  # section titles, summary metric values
          body: 9,      # table cells, subtitles
          small: 8,     # table headers, summary labels, hotel address, metadata values
          micro: 7      # metadata labels, footer
        }.freeze

        # Vertical rhythm on a 4pt grid.
        SPACE = { xs: 4, sm: 8, md: 12, lg: 16, xl: 20 }.freeze

        # Hairline. Prawn defaults to 1pt, which reads heavier than the table borders.
        RULE_WIDTH = 0.5

        # Every document that wears the shared frame shares its measure.
        PAGE_MARGIN = [ 40, 32, 42, 32 ].freeze

        # One date and one time format across every report. %-I drops the leading zero
        # that a 12-hour clock should not carry.
        DATE_FORMAT = "%d %b %Y"
        DATE_TIME_FORMAT = "%d %b %Y, %-I:%M %p"

        def self.format_date(date) = date&.strftime(DATE_FORMAT)

        def self.format_time(time, time_zone) = time&.in_time_zone(time_zone)&.strftime(DATE_TIME_FORMAT)

        # Horizontal cell padding stays at 6 rather than moving onto the grid: report
        # services pass column widths tuned against it, and widening it overflows the
        # denser tables.
        TABLE_CELL_PADDING = [ SPACE[:xs], 6 ].freeze
        SUMMARY_CELL_PADDING = [ SPACE[:sm], SPACE[:sm] ].freeze

        # Vendored so dev and production render identically. Public Sans carries the
        # text; its tabular figures are frozen into the files so money columns line up
        # (Prawn cannot reach OpenType features like tnum at render time).
        TEXT_FAMILY = "Public Sans"
        DISPLAY_FAMILY = "Bricolage Grotesque"
        FALLBACK_FAMILY = "Unicode Fallback"

        # Latin only, so non-Latin guest names fall through to a system CJK face.
        CJK_FONT_CANDIDATES = [
          {
            normal: "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
            bold: "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
          },
          {
            normal: "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf",
            bold: "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf"
          },
          {
            normal: "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            bold: "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
          },
          {
            normal: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
            bold: "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"
          }
        ].freeze

        def self.configure_font(pdf)
          pdf.font_families.update(TEXT_FAMILY => text_font_paths, DISPLAY_FAMILY => display_font_paths)
          paths = cjk_font_paths
          if paths
            pdf.font_families.update(
              FALLBACK_FAMILY => {
                normal: paths.fetch(:normal), bold: paths.fetch(:bold),
                italic: paths.fetch(:normal), bold_italic: paths.fetch(:bold)
              }
            )
            pdf.fallback_fonts = [ FALLBACK_FAMILY ]
          end
          pdf.font(TEXT_FAMILY)
        end

        def self.font_dir = Rails.root.join("app/assets/fonts")

        def self.text_font_paths
          {
            normal: font_dir.join("PublicSans-Regular.ttf").to_s,
            bold: font_dir.join("PublicSans-Bold.ttf").to_s,
            italic: font_dir.join("PublicSans-Italic.ttf").to_s,
            bold_italic: font_dir.join("PublicSans-BoldItalic.ttf").to_s
          }
        end

        # Display weight only — Bricolage is for mastheads and titles, never table data.
        def self.display_font_paths
          bold = font_dir.join("BricolageGrotesque-Bold.ttf").to_s
          { normal: bold, bold: bold, italic: bold, bold_italic: bold }
        end

        # Optional: without it, non-Latin characters render as blanks rather than
        # failing the export outright.
        def self.cjk_font_paths
          override = ENV["WASTAYS_PDF_UNICODE_FONT_PATH"].presence
          candidates = []
          if override
            candidates << {
              normal: override,
              bold: ENV["WASTAYS_PDF_UNICODE_BOLD_FONT_PATH"].presence || override
            }
          end
          candidates.concat(CJK_FONT_CANDIDATES)
          paths = candidates.find { |candidate| candidate.values.all? { |path| File.file?(path) } }
          if paths.nil?
            Rails.logger.warn(
              "PDF CJK fallback font not found; non-Latin text will render blank. " \
              "Install fonts-noto-cjk or set WASTAYS_PDF_UNICODE_FONT_PATH."
            )
          end
          paths
        end
      end
    end
  end
end
