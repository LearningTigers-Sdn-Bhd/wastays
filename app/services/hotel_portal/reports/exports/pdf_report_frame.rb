# frozen_string_literal: true

require "stringio"

module HotelPortal
  module Reports
    module Exports
      class PdfReportFrame
        FOOTER_Y = -9
        PAGE_NUMBER_WIDTH = 90
        HOTEL_LOGO_SIZE = 44
        COMPACT_HOTEL_LOGO_SIZE = 32
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
        # Air between the title and the badge it is set against, so the two never touch on
        # a title long enough to reach for the slot.
        BADGE_GUTTER = PdfTheme::SPACE[:md]
        # Between two badges sharing the slot. Tighter than the gutter that separates the
        # pair from the title: they are one group, set apart from what they sit beside.
        BADGE_GAP = PdfTheme::SPACE[:sm]
        # Keeps a long hotel name from running under the badge set opposite it.
        MASTHEAD_BADGE_GUTTER = PdfTheme::SPACE[:md]
        # Sits in the top margin, mirroring how the footer sits below the content box.
        RUNNING_HEAD_Y = 18
        COMPACT_TITLE_SHARE = 0.36
        COMPACT_COLUMN_GUTTER = PdfTheme::SPACE[:md]
        VARIANTS = %i[standard compact].freeze

        def initialize(pdf:, hotel:, report_name:, period_label: nil, prepared_by: nil, period_label_title: "Period", subtitle: nil, eyebrow: nil, metadata: nil, generated_at: Time.current, confidential: true, hotel_identifiers: nil, badge: nil, masthead_badge: nil, title_accessory: nil, variant: :standard)
          @pdf = pdf
          @hotel = hotel
          @hotel_identifiers = hotel_identifiers
          @badge = badge
          @masthead_badge = masthead_badge
          @title_accessory = title_accessory
          @report_name = report_name
          @subtitle = subtitle
          @eyebrow = eyebrow
          @period_label_title = period_label_title
          @period_label = period_label
          @prepared_by = prepared_by
          @metadata = metadata
          @generated_at = generated_at
          @confidential = confidential
          @variant = variant.to_sym
          raise ArgumentError, "Unknown PDF report frame variant: #{variant}" unless VARIANTS.include?(@variant)
        end

        def draw_header
          @pdf.line_width PdfTheme::RULE_WIDTH
          if @variant == :compact
            draw_compact_header
          else
            draw_hotel_identity
            draw_report_identity
            draw_metadata
          end
        end

        # Call once, after all content is drawn. A document that draws a masthead on more
        # than its first page — an original and its duplicate copy — names those pages, so
        # they do not get a running head on top of the masthead they already carry.
        def stamp_page_furniture(masthead_pages: [ 1 ])
          stamp_running_head(masthead_pages:)
          stamp_footer
        end

        # Continuation pages carry no masthead, so on their own they identify neither the
        # hotel nor the report. A detached page 2 needs to say what it belongs to.
        def stamp_running_head(masthead_pages: [ 1 ])
          label = [ @hotel.name, @eyebrow.presence || @report_name, @period_label ].compact_blank.join("  ·  ")
          @pdf.repeat(->(page) { masthead_pages.exclude?(page) }) do
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
          # #number_pages draws a text box, whose :at is the top of the box, while the two
          # items beside it are drawn at their baseline. Without the ascender the page
          # number hangs a line below the rest of the footer.
          @pdf.font_size(PdfTheme::TYPE[:micro]) do
            @pdf.number_pages(
              "Page <page> of <total>",
              at: [ @pdf.bounds.width - PAGE_NUMBER_WIDTH, FOOTER_Y + @pdf.font.ascender ],
              width: PAGE_NUMBER_WIDTH, align: :right, size: PdfTheme::TYPE[:micro],
              color: PdfTheme::COLORS[:muted]
            )
          end
        end

        private

        # Advances by what the text actually occupies rather than a fixed constant, so a
        # two-line hotel name or address can never collide with the rule below it.
        def draw_hotel_identity(logo_size: HOTEL_LOGO_SIZE, detail_lines: nil, rule_gap: MASTHEAD_RULE_GAP)
          top = @pdf.cursor
          logo = hotel_logo
          text_left = logo ? logo_size + LOGO_GUTTER : 0
          text_width = @pdf.bounds.width - text_left - masthead_badge_reserve
          name = @hotel.name.to_s

          @pdf.image logo, at: [ 0, top ], fit: [ logo_size, logo_size ] if logo
          draw_masthead_badge(top)

          @pdf.fill_color PdfTheme::COLORS[:ink]
          name_size = PdfTheme::TYPE[:subhead]
          name_height = @pdf.height_of(name, width: text_width, size: name_size, style: :bold)
          @pdf.text_box name, at: [ text_left, top ], width: text_width, height: name_height,
            size: name_size, style: :bold
          text_bottom = top - name_height

          # A document that bills in the hotel's name has to print how to reach it, and a
          # tax document how it is registered. The reports need neither, so both lines are
          # the caller's to ask for.
          (detail_lines || [ hotel_address, hotel_contact, @hotel_identifiers ]).compact_blank.each do |line|
            @pdf.fill_color PdfTheme::COLORS[:muted]
            line_size = PdfTheme::TYPE[:small]
            line_top = text_bottom - NAME_ADDRESS_GAP
            line_height = @pdf.height_of(line, width: text_width, size: line_size, leading: 2)
            @pdf.text_box line, at: [ text_left, line_top ], width: text_width,
              height: line_height, size: line_size, leading: 2
            text_bottom = line_top - line_height
          end

          @pdf.move_cursor_to [ text_bottom, logo ? top - logo_size : text_bottom ].min
          @pdf.move_down rule_gap
          @pdf.stroke_color PdfTheme::COLORS[:border]
          @pdf.stroke_horizontal_rule
          @pdf.move_down TITLE_GAP_ABOVE
        end

        # The title carries the display face; the hotel name above it stays in the text
        # face, so the two are separated by typeface rather than by size alone. The whole
        # identity is measured as a row: ordinary documents place a badge against the title,
        # while documents such as a reservation voucher can supply a taller accessory. The
        # cursor clears whichever column is taller, so the metadata below cannot collide with
        # a QR code or another out-of-flow object.
        def draw_report_identity
          top = @pdf.cursor
          left = draw_report_identity_left(top)
          accessory_height = draw_report_identity_right(top, left)
          @pdf.move_cursor_to top - [ left[:height], accessory_height ].max
          @pdf.move_down TITLE_GAP_BELOW
        end

        def draw_report_identity_left(top, width: identity_left_width)
          cursor = top

          if @eyebrow.present?
            options = {
              size: PdfTheme::TYPE[:micro], style: :bold,
              character_spacing: METADATA_LABEL_TRACKING
            }
            text = @eyebrow.to_s.upcase
            height = @pdf.height_of(text, width: width, **options)
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.text_box text, at: [ 0, cursor ], width: width, height: height, **options
            cursor -= height + EYEBROW_GAP
          end

          title_top = cursor
          title_height = draw_report_title(title_top, width)
          cursor -= title_height

          if @subtitle.present?
            cursor -= TITLE_SUBTITLE_GAP
            options = { size: PdfTheme::TYPE[:body] }
            height = @pdf.height_of(@subtitle.to_s, width: width, **options)
            @pdf.fill_color PdfTheme::COLORS[:muted]
            @pdf.text_box @subtitle.to_s, at: [ 0, cursor ], width: width, height: height, **options
            cursor -= height
          end

          { height: top - cursor, title_top: title_top, title_height: title_height }
        end

        def draw_report_title(top, width)
          title = @report_name.to_s
          options = { size: PdfTheme::TYPE[:display] }

          # Prawn's #font returns the font it set, not what the block evaluated to, so a
          # measurement taken inside one has to be carried out in a local.
          height = nil
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.font(PdfTheme::DISPLAY_FAMILY) do
            height = @pdf.height_of(title, width: width, **options)
            @pdf.text_box title, at: [ 0, top ], width: width, height: height, **options
          end
          height
        end

        # The slot takes as many badges as the document has facts to set against its title.
        # They are laid out from the right margin inwards, so a document adding a second
        # badge leaves the first exactly where every other document puts it.
        def draw_report_identity_right(top, left)
          return draw_title_accessory(top) if @title_accessory
          return 0 if badges.empty?

          badge = PdfBadge.new(pdf: @pdf)
          line = nil
          @pdf.font(PdfTheme::DISPLAY_FAMILY) { line = @pdf.height_of("X", size: PdfTheme::TYPE[:display]) }
          badge_top = left[:title_top] - ((line - badge.height) / 2.0)
          @pdf.fill_color PdfTheme::COLORS[:ink]

          right = @pdf.bounds.width
          badges.reverse_each do |entry|
            right -= badge.width(entry[:label])
            badge.draw(label: entry[:label], at: [ right, badge_top ], variant: entry[:variant])
            right -= BADGE_GAP
          end
          top - badge_top + badge.height
        end

        def draw_title_accessory(top)
          @title_accessory.draw(at: [ @pdf.bounds.width - @title_accessory.width, top ])
          @title_accessory.height
        end

        def identity_left_width
          @pdf.bounds.width - identity_right_width
        end

        def identity_right_width
          width = if @title_accessory
            @title_accessory.width
          elsif badges.any?
            badge = PdfBadge.new(pdf: @pdf)
            badges.sum { |entry| badge.width(entry[:label]) } + (BADGE_GAP * (badges.size - 1))
          else
            0
          end
          # An accessory too wide to set a title beside keeps the measure to itself rather
          # than starving the title column of every point it has.
          return 0 if width.zero? || width >= @pdf.bounds.width

          width + BADGE_GUTTER
        end

        # Sits at the very top of the sheet, opposite the hotel identity, above even the
        # report title. That height is for a fact about the piece of paper rather than
        # about the document on it — which copy of it you are holding — so it is read
        # before the reader is into the document at all. Facts about the document itself
        # belong on the title row with `badge:`.
        def draw_masthead_badge(top)
          return if masthead_badge.nil?

          badge = PdfBadge.new(pdf: @pdf)
          label = masthead_badge.fetch(:label)
          badge.draw(
            label: label,
            at: [ @pdf.bounds.width - badge.width(label), top ],
            variant: masthead_badge[:variant] || :outline
          )
        end

        def masthead_badge_reserve
          return 0 if masthead_badge.nil?

          PdfBadge.new(pdf: @pdf).width(masthead_badge.fetch(:label)) + MASTHEAD_BADGE_GUTTER
        end

        def masthead_badge
          entry = @masthead_badge.is_a?(Hash) ? @masthead_badge : { label: @masthead_badge }
          entry[:label].blank? ? nil : entry
        end

        # badge: takes a string, a { label:, variant: } hash, or an array of either. One
        # badge is the ordinary case and stays a bare hash at the call site.
        def badges
          @badges ||= Array.wrap(@badge).filter_map do |entry|
            label = entry.is_a?(Hash) ? entry[:label] : entry
            next if label.blank?

            { label: label, variant: (entry.is_a?(Hash) ? entry[:variant] : nil) || :neutral }
          end
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

        def draw_compact_header
          details = [ hotel_address, hotel_contact, @hotel_identifiers ].compact_blank.join(" | ")
          draw_hotel_identity(
            logo_size: COMPACT_HOTEL_LOGO_SIZE,
            detail_lines: [ details ],
            rule_gap: PdfTheme::SPACE[:sm]
          )
          draw_compact_report_identity
        end

        def draw_compact_report_identity
          top = @pdf.cursor
          metadata = metadata_pairs
          metadata_width = metadata.empty? ? 0 : @pdf.bounds.width * (1 - COMPACT_TITLE_SHARE)
          title_width = @pdf.bounds.width - metadata_width
          title_width -= COMPACT_COLUMN_GUTTER if metadata_width.positive?

          title = draw_report_identity_left(top, width: title_width)
          metadata_height = draw_compact_metadata(
            metadata,
            left: title_width + COMPACT_COLUMN_GUTTER,
            top:,
            width: metadata_width
          )

          @pdf.move_cursor_to top - [ title[:height], metadata_height ].max
          @pdf.move_down PdfTheme::SPACE[:sm]
          @pdf.stroke_color PdfTheme::COLORS[:border]
          @pdf.stroke_horizontal_rule
          @pdf.move_down PdfTheme::SPACE[:md]
          @pdf.fill_color PdfTheme::COLORS[:ink]
        end

        def draw_compact_metadata(metadata, left:, top:, width:)
          return 0 if metadata.empty?

          widths = Array.new(metadata.size, width / metadata.size)
          offsets = widths.each_with_index.map { |_, index| left + widths[0...index].sum }
          label_height = draw_metadata_row(
            metadata.map { |(label, _)| label.to_s.upcase }, widths, offsets, top,
            size: PdfTheme::TYPE[:micro], style: :bold, color: PdfTheme::COLORS[:muted],
            character_spacing: METADATA_LABEL_TRACKING, gutter: PdfTheme::SPACE[:sm]
          )
          value_top = top - label_height - METADATA_LABEL_GAP
          value_height = draw_metadata_row(
            metadata.map { |(_, value)| value.to_s }, widths, offsets, value_top,
            size: PdfTheme::TYPE[:small], style: :normal, color: PdfTheme::COLORS[:ink],
            gutter: PdfTheme::SPACE[:sm]
          )
          top - value_top + value_height
        end

        # Draws one row of the metadata strip and reports the height of its tallest column.
        def draw_metadata_row(texts, widths, offsets, top, size:, style:, color:, character_spacing: 0,
          gutter: METADATA_GUTTER)
          @pdf.fill_color color
          options = { size: size, style: style, character_spacing: character_spacing }
          heights = texts.each_with_index.map do |text, index|
            width = widths[index] - gutter
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

        # Hotels type the city, and often the state with it, into the address line itself,
        # so joining the three parts prints Langkawi twice. uniq cannot see it — the parts
        # are different strings and the repeat sits inside one of them — so a part is
        # dropped when what has already been kept names it.
        # Every masthead names how to reach the hotel about the document it sits on, so the
        # line is built here rather than passed in by each document. Every way of reaching
        # it is named whether or not it publishes one — a dash says the number is absent,
        # where dropping the label leaves a reader unable to tell a hotel without a landline
        # from a document that failed to print the landline it had. A hotel publishing none
        # of the three prints no line at all rather than a row of dashes.
        #
        # A document whose masthead is a snapshot passes contact details that are current
        # anyway: the identity is as it was, but a number the hotel stopped answering serves
        # nobody.
        def hotel_contact
          parts = [
            [ "Fixed line", @hotel.try(:fixed_line_number) ],
            [ "Phone", @hotel.try(:contact_phone) ],
            [ "Email", @hotel.try(:contact_email) ]
          ]
          return if parts.none? { |_label, value| value.present? }

          parts.map { |label, value| "#{label}: #{value.presence || '-'}" }.join(" · ")
        end

        def hotel_address
          [ @hotel.try(:address), @hotel.try(:city), @hotel.try(:country) ]
            .compact_blank
            .each_with_object([]) { |part, kept| kept << part unless already_named?(kept, part) }
            .join(", ")
        end

        def already_named?(kept, part)
          pattern = /\b#{Regexp.escape(part.to_s.strip)}\b/i
          kept.any? { |line| line.match?(pattern) }
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

        # The wordmark is set as text rather than placed as the logo image: at footer size
        # the bitmap read as a smudge, and the name keeps its weight against the label.
        def draw_wastays_attribution
          label = "Generated by "
          name = "WAStays.com"
          size = PdfTheme::TYPE[:micro]
          label_width = @pdf.width_of(label, size: size)
          name_width = @pdf.width_of(name, size: size, style: :bold)
          left = (@pdf.bounds.width - (label_width + name_width)) / 2.0
          @pdf.draw_text label, at: [ left, FOOTER_Y ], size: size
          @pdf.fill_color PdfTheme::COLORS[:ink]
          @pdf.draw_text name, at: [ left + label_width, FOOTER_Y ], size: size, style: :bold
        end
      end
    end
  end
end
