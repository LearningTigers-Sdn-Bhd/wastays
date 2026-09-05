# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

class GuestRegistrationCardPdfService
  THEME = HotelPortal::Reports::Exports::PdfTheme

  # Aliases onto the shared palette, so the card reads as the same family of document as
  # the reports rather than carrying its own greys.
  BORDER      = THEME::COLORS[:border]
  TEXT        = THEME::COLORS[:ink]
  TEXT_MUTED  = THEME::COLORS[:muted]
  DUE_RED     = THEME::COLORS[:danger]

  def initialize(card, booking, presenter)
    @card = card
    @booking = booking
    @hotel = booking.hotel
    @presenter = presenter
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: THEME::PAGE_MARGIN,
      info: {
        Title: "Guest Registration Card - #{@booking.guest_registration_card_number_display}",
        Author: "WAStays",
        Creator: "WAStays",
        CreationDate: Time.current
      }
    )
    THEME.configure_font(pdf)
    frame = build_frame(pdf)

    frame.draw_header
    # Pulls the Name/Phone row up closer to the metadata strip above it — the
    # frame's own gap is sized for reports with a section title in between,
    # which this card doesn't have.
    pdf.move_up 10
    draw_bordered_section(pdf, bottom_margin: 2) { draw_guest_section(pdf) }
    draw_bordered_section(pdf, bottom_margin: 2) { draw_stay_section(pdf) }
    draw_bordered_section(pdf, bottom_margin: @presenter.boat_transfer? ? 2 : 5) { draw_payment_section(pdf) }
    draw_bordered_section(pdf) { draw_boat_transfer_section(pdf) } if @presenter.boat_transfer?
    draw_policy_section(pdf)
    draw_bordered_section(pdf) { draw_notes_section(pdf, "Remark", @booking.special_requests) } if @booking.special_requests.present?
    pdf.move_down THEME::SPACE[:md]
    draw_signature_section(pdf)
    frame.stamp_page_furniture

    pdf.render
  end

  private

  # The title is the card number, so the eyebrow carries what kind of document this is.
  def build_frame(pdf)
    HotelPortal::Reports::Exports::PdfReportFrame.new(
      pdf: pdf,
      hotel: @hotel,
      hotel_identifiers: @presenter.hotel_registration_display,
      eyebrow: "Guest Registration Card",
      report_name: @booking.guest_registration_card_number_display,
      metadata: [
        [ "Booking", @booking.confirmation_token ],
        [ "Issued", THEME.format_time(Time.current, @hotel.hotel_time_zone) ]
      ]
    )
  end

  def draw_bordered_section(pdf, bottom_margin: 5)
    yield
    pdf.move_down 2
    pdf.stroke_color BORDER
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.move_down bottom_margin
  end

  def draw_guest_section(pdf)
    rows = [ [ "Name", @presenter.guest_name ] ]
    rows << [ "Phone", @presenter.guest_phone ] if @card.field_visible?(:phone)
    rows << [ "Email", @presenter.guest_email ] if @card.field_visible?(:email)
    rows << [ "Country", @presenter.guest_country_display ]
    rows << [ "Guests", @presenter.guest_count_display ] if @card.field_visible?(:guest_count)
    rows << [ "Identity", @presenter.guest_identity ]

    draw_label_value_grid(pdf, rows)
  end

  def draw_stay_section(pdf)
    rows = []
    rows << [ "Booking", @booking.confirmation_token ] if @card.field_visible?(:booking_number)
    rows << [ "Room type", @presenter.room_type_summary ] if @card.field_visible?(:room_type)
    rows << [ "Room(s)", @presenter.room_numbers_display ] if @card.field_visible?(:room_number)
    rows << [ "Rate type", @presenter.rate_type_display ]
    rows << [ "Night(s)", @booking.duration_in_nights.to_s ]
    draw_label_value_grid(pdf, rows) if rows.any?

    dates = []
    dates << [ "Check-in", @presenter.check_in_display ] if @card.field_visible?(:check_in)
    dates << [ "Check-out", @presenter.check_out_display ] if @card.field_visible?(:check_out)
    draw_label_value_grid(pdf, dates) if dates.any?
  end

  def draw_payment_section(pdf)
    rows = [
      [ "Room price", @presenter.room_price_display ],
      [ "Amount paid", @presenter.format_money(@presenter.amount_paid) ],
      [ "Total charges", @presenter.format_money(@presenter.total_charges) ],
      [ "Tax", @presenter.format_money(@booking.tax_total) ],
      [ "Due amount", @presenter.format_money(@presenter.due_amount), DUE_RED ]
    ]

    draw_label_value_grid(pdf, rows)
  end

  def draw_boat_transfer_section(pdf)
    draw_label_value_grid(pdf, [
      [ "Boat-in", @presenter.boat_in_display ],
      [ "Boat-out", @presenter.boat_out_display ]
    ])
  end

  def draw_policy_section(pdf)
    draw_terms_and_conditions(pdf)

    summary = @presenter.cancellation_summary
    pdf.fill_color TEXT
    if summary.present?
      pdf.text "Cancellation Policy", size: 8, style: :bold
      pdf.move_down 2
      draw_cancellation_tiers(pdf, summary.rows)
      draw_cancellation_notes(pdf, summary)
    elsif @presenter.terms_and_conditions.blank?
      # Only worth a line when the whole policy section would otherwise be
      # empty — with terms and conditions already shown above, a missing
      # cancellation policy on its own isn't worth calling out here.
      pdf.fill_color TEXT_MUTED
      pdf.text "Hotel terms are not configured.", size: 9
    end
    pdf.move_down 12
  end

  # Generated from the stored tier rows — the schedule the guest signs against is
  # the same one the folio charges from.
  def draw_cancellation_tiers(pdf, rows)
    return if rows.empty?

    data = [ [ "If cancelled", "Charge" ] ] + rows.map { |row| [ row.window, row.charge ] }
    pdf.table(data, width: pdf.bounds.width, cell_style: { size: 8, padding: [ 3, 5 ], border_color: BORDER, border_width: 0.5 }) do
      row(0).font_style = :bold
    end
    pdf.move_down 4
  end

  # The hotel's fixed policy, set once in Settings rather than per booking —
  # printed ahead of the cancellation tiers, which stay their own section since
  # they're computed, not authored.
  def draw_terms_and_conditions(pdf)
    text = @presenter.terms_and_conditions
    return if text.blank?

    pdf.fill_color TEXT
    pdf.text "Terms & Conditions", size: 8, style: :bold
    pdf.move_down 2
    pdf.text text, size: 9, leading: 2
    pdf.move_down 10
  end

  def draw_cancellation_notes(pdf, summary)
    pdf.fill_color TEXT_MUTED
    notes = [ summary.refund_note, summary.description, summary.structured? ? nil : summary.legacy_text ].compact
    notes.each do |note|
      pdf.text note, size: 9, leading: 2
      pdf.move_down 2
    end
  end

  def draw_notes_section(pdf, title, text)
    section_title(pdf, title)
    pdf.fill_color TEXT
    pdf.text text, size: 9, leading: 2
  end

  def draw_signature_section(pdf)
    box_width = pdf.bounds.width / 2.0
    box_left = pdf.bounds.width - box_width
    top = pdf.cursor
    height = 90

    pdf.stroke_color BORDER
    pdf.line_width 0.5
    pdf.stroke_rectangle [ box_left, top ], box_width, height

    pdf.fill_color TEXT_MUTED
    pdf.text_box "Guest signature", at: [ box_left + 10, top - 14 ], size: 8, style: :bold

    if @presenter.signed_for_active_guest?
      signature_io = decode_signature(@presenter.signature_data_url)
      draw_signature_image(pdf, signature_io, at: [ box_left + 10, top - 26 ], height: 40) if signature_io
      pdf.fill_color TEXT_MUTED
      signed_at_str = @presenter.signed_at ? l(@presenter.signed_at, format: :long) : ""
      pdf.text_box "Signed by #{@presenter.signer_name} at #{signed_at_str}",
        at: [ box_left + 10, top - 74 ], width: box_width - 20, size: 8
    else
      pdf.stroke_color BORDER
      pdf.line_width 0.5
      pdf.line [ box_left + 10, top - 60 ], [ box_left + box_width - 10, top - 60 ]
      pdf.fill_color TEXT_MUTED
      pdf.text_box "Signature", at: [ box_left + 10, top - 72 ], size: 8
    end

    pdf.move_down height
  end

  def draw_label_value_grid(pdf, rows)
    pairs = rows.each_slice(2).to_a

    data = pairs.map do |(left, right)|
      [
        label_cell(left[0]), value_cell(left[1], left[2]),
        right ? label_cell(right[0]) : blank_cell,
        right ? value_cell(right[1], right[2]) : blank_cell
      ]
    end

    w = pdf.bounds.width
    label_w = 90
    value_w = (w / 2.0 - label_w).floor
    last_value_w = w - (label_w * 2 + value_w)

    pdf.table(data, width: w, column_widths: [ label_w, value_w, label_w, last_value_w ])
    pdf.move_down 2
  end

  def label_cell(text)
    { content: text, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 1, 4, 1, 0 ] }
  end

  def value_cell(text, color = nil)
    { content: ": #{text.to_s.presence || '-'}", size: 9, text_color: color || TEXT, borders: [], padding: [ 1, 8, 1, 0 ] }
  end

  def blank_cell
    { content: "", borders: [] }
  end

  def section_title(pdf, text)
    pdf.fill_color TEXT
    pdf.text text, size: 9, style: :bold
    pdf.move_down 6
  end

  def decode_signature(data_url)
    match = data_url.match(/\Adata:image\/\w+;base64,(.+)\z/m)
    return nil unless match

    StringIO.new(Base64.decode64(match[1]))
  rescue ArgumentError
    nil
  end

  def draw_signature_image(pdf, signature_io, **options)
    pdf.image signature_io, **options
  rescue Prawn::Errors::UnsupportedImageType
    nil
  end

  def l(object, **options)
    I18n.l(object, **options)
  end
end
