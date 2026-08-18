# frozen_string_literal: true

require "stringio"

module HotelPortal
  module Reports
    module Exports
      class PdfReportFrame
        FOOTER_Y = -9
        HOTEL_LOGO_SIZE = 44
        WASTAYS_LOGO_WIDTH = 50
        LOGO_GUTTER = PdfTheme::SPACE[:md]
        NAME_ADDRESS_GAP = PdfTheme::SPACE[:xs]
        # The title binds to the metadata strip it describes, so it sits closer to
        # what follows it than to the masthead rule above.
        MASTHEAD_RULE_GAP = PdfTheme::SPACE[:md]
        # Tight to the masthead rule: the font's own leading carries most of the air above
        # the title, so this only needs the smallest step on the grid.
        TITLE_GAP_ABOVE = PdfTheme::SPACE[:xs]
        TITLE_SUBTITLE_GAP = PdfTheme::SPACE[:xs]
        TITLE_GAP_BELOW = PdfTheme::SPACE[:xs]
        METADATA_RULE_GAP = PdfTheme::SPACE[:sm]
        METADATA_LABEL_GAP = PdfTheme::SPACE[:xs]
        METADATA_GUTTER = PdfTheme::SPACE[:xl]
        METADATA_GAP_BELOW = PdfTheme::SPACE[:xl]
        # Shared with the stat strip, which marks its label tier the same way.
        METADATA_LABEL_TRACKING = PdfTheme::LABEL_TRACKING
        EYEBROW_GAP = PdfTheme::SPACE[:xs]
        # Sits in the top margin, mirroring how the footer sits below the content box.
        RUNNING_HEAD_Y = 18

        def initialize(pdf:, hotel:, report_name:, period_label: nil, prepared_by: nil, period_label_title: "Period", subtitle: nil, eyebrow: nil, metadata: nil, generated_at: Time.current, confidential: true, hotel_contact: nil)
          @pdf = pdf
          @hotel = hotel
          @hotel_contact = hotel_contact
          @report_name = report_name
          @subtitle = subtitle
          @eyebrow = eyebrow
          @period_label_title = period_label_title
          @period_label = period_label
          @prepared_by = prepared_by
          @metadata = metadata
          @generated_at = generated_at
          @confidential = confidential
        end

        def draw_header
          @pdf.line_width PdfTheme::RULE_WIDTH
          draw_hotel_identity
          draw_report_identity
          draw_metadata
        end

        # Call once, after all content is drawn.
        def stamp_page_furniture
          stamp_running_head
          stamp_footer
        end

        # Continuation pages carry no masthead, so on their own they identify neither the
        # hotel nor the report. A detached page 2 needs to say what it belongs to.
        def stamp_running_head
          label = [ @hotel.name, @eyebrow.presence || @report_name, @period_label ].compact_blank.join("  ·  ")
          @pdf.repeat(->(page) { page > 1 }) do
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.draw_text label, at: [ 0, @pdf.bounds.top + RUNNING_HEAD_Y ], size: PdfTheme::TYPE[:micro]
          end
        end

        def stamp_footer
          @pdf.repeat(:all) do
            @pdf.stroke_color PdfTheme::COLORS[:border]
            @pdf.line_width PdfTheme::RULE_WIDTH
            @pdf.stroke_horizontal_line 0, @pdf.bounds.width, at: 2
            @pdf.fill_color PdfTheme::COLORS[:muted]
            # Internal reports are marked; a document that goes to the guest is not.
            @pdf.draw_text "Confidential", at: [ 0, FOOTER_Y ], size: PdfTheme::TYPE[:micro] if @confidential
            draw_wastays_attribution
          end
          @pdf.number_pages(
            "Page <page> of <total>",
            at: [ @pdf.bounds.width - 90, FOOTER_Y ], width: 90, align: :right, size: PdfTheme::TYPE[:micro],
            color: PdfTheme::COLORS[:muted]
          )
        end

        private

        # Advances by what the text actually occupies rather than a fixed constant, so a
        # two-line hotel name or address can never collide with the rule below it.
        def draw_hotel_identity
          top = @pdf.cursor
          logo = hotel_logo
          text_left = logo ? HOTEL_LOGO_SIZE + LOGO_GUTTER : 0
          text_width = @pdf.bounds.width - text_left
          name = @hotel.name.to_s
          address = hotel_address

          @pdf.image logo, at: [ 0, top ], fit: [ HOTEL_LOGO_SIZE, HOTEL_LOGO_SIZE ] if logo

          @pdf.fill_color PdfTheme::COLORS[:ink]
          name_size = PdfTheme::TYPE[:subhead]
          name_height = @pdf.height_of(name, width: text_width, size: name_size, style: :bold)
          @pdf.text_box name, at: [ text_left, top ], width: text_width, height: name_height,
            size: name_size, style: :bold
          text_bottom = top - name_height

          # A document that bills in the hotel's name has to print how to reach it. The
          # reports do not, so the contact line is the caller's to ask for.
          [ address, @hotel_contact ].compact_blank.each do |line|
            @pdf.fill_color PdfTheme::COLORS[:muted]
            line_size = PdfTheme::TYPE[:small]
            line_top = text_bottom - NAME_ADDRESS_GAP
            line_height = @pdf.height_of(line, width: text_width, size: line_size, leading: 2)
            @pdf.text_box line, at: [ text_left, line_top ], width: text_width,
              height: line_height, size: line_size, leading: 2
            text_bottom = line_top - line_height
          end

          @pdf.move_cursor_to [ text_bottom, logo ? top - HOTEL_LOGO_SIZE : text_bottom ].min
          @pdf.move_down MASTHEAD_RULE_GAP
          @pdf.stroke_color PdfTheme::COLORS[:border]
          @pdf.stroke_horizontal_rule
          @pdf.move_down TITLE_GAP_ABOVE
        end

        # The title carries the display face; the hotel name above it stays in the text
        # face, so the two are separated by typeface rather than by size alone. An eyebrow
        # lets a document whose title is an identifier still name what kind of document it is.
        def draw_report_identity
          if @eyebrow.present?
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.text @eyebrow.to_s.upcase, size: PdfTheme::TYPE[:micro], style: :bold,
              character_spacing: METADATA_LABEL_TRACKING
            @pdf.move_down EYEBROW_GAP
          end
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.font(PdfTheme::DISPLAY_FAMILY) do
            @pdf.text @report_name.to_s, size: PdfTheme::TYPE[:display]
          end
          if @subtitle.present?
            @pdf.move_down TITLE_SUBTITLE_GAP
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.text @subtitle.to_s, size: PdfTheme::TYPE[:body]
          end
          @pdf.move_down TITLE_GAP_BELOW
        end

        # Rules rather than a tint: the fill made three short values read as an empty
        # table header, and forced padding that broke the page's left margin.
        def draw_metadata
          metadata = metadata_pairs
          return if metadata.empty?

          # Drawn directly rather than as a table: prawn-table cells reject
          # character_spacing, and measuring the boxes here keeps the closing rule tight
          # against the tallest column whatever it holds.
          widths = metadata_column_widths(metadata.size)
          offsets = widths.each_with_index.map { |_, index| widths[0...index].sum }

          @pdf.stroke_color PdfTheme::COLORS[:border]
          @pdf.stroke_horizontal_rule
          @pdf.move_down METADATA_RULE_GAP

          top = @pdf.cursor
          label_height = draw_metadata_row(
            metadata.map { |(label, _)| label.to_s.upcase }, widths, offsets, top,
            size: PdfTheme::TYPE[:micro], style: :bold, color: PdfTheme::COLORS[:muted],
            character_spacing: METADATA_LABEL_TRACKING
          )
          value_top = top - label_height - METADATA_LABEL_GAP
          value_height = draw_metadata_row(
            metadata.map { |(_, value)| value.to_s }, widths, offsets, value_top,
            size: PdfTheme::TYPE[:small], style: :normal, color: PdfTheme::COLORS[:ink]
          )

          @pdf.move_cursor_to value_top - value_height
          @pdf.move_down METADATA_RULE_GAP
          @pdf.stroke_horizontal_rule
          @pdf.move_down METADATA_GAP_BELOW
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        # Draws one row of the metadata strip and reports the height of its tallest column.
        def draw_metadata_row(texts, widths, offsets, top, size:, style:, color:, character_spacing: 0)
          @pdf.fill_color color
          options = { size: size, style: style, character_spacing: character_spacing }
          heights = texts.each_with_index.map do |text, index|
            width = widths[index] - METADATA_GUTTER
            height = @pdf.height_of(text, width: width, **options)
            @pdf.text_box text, at: [ offsets[index], top ], width: width, height: height, **options
            height
          end
          heights.max
        end

        # Documents that are not period-based supply their own pairs; everything else gets
        # the standard three.
        def metadata_pairs
          pairs = @metadata || [
            [ @period_label_title, @period_label ],
            [ "Generated", generated_label ],
            [ "Prepared by", @prepared_by ]
          ]
          pairs.reject { |(label, value)| label.blank? || value.blank? }
        end

        def metadata_column_widths(count)
          width = @pdf.bounds.width
          widths = Array.new(count, (width / count).floor)
          widths[-1] += width - widths.sum
          widths
        end

        def hotel_address
          [ @hotel.try(:address), @hotel.try(:city), @hotel.try(:country) ].compact_blank.join(", ")
        end

        def generated_label
          PdfTheme.format_time(@generated_at, @hotel.hotel_time_zone)
        end

        def hotel_logo
          return unless @hotel.respond_to?(:icon) && @hotel.icon.attached?

          variant = @hotel.icon.variant(resize_to_limit: [ 96, 96 ], format: :png).processed
          StringIO.new(variant.download)
        rescue StandardError => error
          Rails.logger.warn("PDF hotel logo unavailable for hotel #{@hotel.id}: #{error.class}: #{error.message}")
          nil
        end

        def draw_wastays_attribution
          logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
          label = "Generated by"
          size = PdfTheme::TYPE[:micro]
          # Measured rather than assumed: the hardcoded width this used to carry was wider
          # than the label, which pushed the whole group off centre.
          label_width = @pdf.width_of(label, size: size)
          gap = PdfTheme::SPACE[:xs]
          group_width = label_width + gap + WASTAYS_LOGO_WIDTH
          left = (@pdf.bounds.width - group_width) / 2.0
          @pdf.draw_text label, at: [ left, FOOTER_Y ], size: size
          return unless File.exist?(logo_path)

          @pdf.image logo_path, at: [ left + label_width + gap, FOOTER_Y + 7 ], width: WASTAYS_LOGO_WIDTH
        end
      end
    end
  end
end
