# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

class GuestRegistrationCardPdfService
  BORDER      = "d1d5db"
  TEXT        = "111827"
  TEXT_MUTED  = "6b7280"
  DUE_RED     = "e11d48"

  def initialize(card, booking, presenter)
    @card = card
    @booking = booking
    @hotel = booking.hotel
    @presenter = presenter
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: [ 40, 40, 40, 40 ],
      info: {
        Title: "Guest Registration Card - #{@booking.guest_registration_card_number_display}",
        Author: "WAStays",
        Creator: "WAStays",
        CreationDate: Time.now
      }
    )
    HotelPortal::Reports::Exports::PdfTheme.configure_font(pdf)

    draw_header(pdf)
    draw_bordered_section(pdf, bottom_margin: 2) { draw_guest_section(pdf) }
    draw_bordered_section(pdf, bottom_margin: 2) { draw_stay_section(pdf) }
    draw_bordered_section(pdf, bottom_margin: @presenter.boat_transfer? ? 2 : 5) { draw_payment_section(pdf) }
    draw_bordered_section(pdf) { draw_boat_transfer_section(pdf) } if @presenter.boat_transfer?
    draw_policy_section(pdf)
    draw_bordered_section(pdf) { draw_notes_section(pdf, "Please Note", @booking.internal_notes) } if @booking.internal_notes.present?
    draw_bordered_section(pdf) { draw_notes_section(pdf, "Remark", @booking.special_requests) } if @booking.special_requests.present?
    pdf.move_down 12
    draw_signature_section(pdf)
    pdf.move_down 16
    draw_footer(pdf)

    pdf.render
  end

  private

  def draw_header(pdf)
    logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
    top = pdf.cursor

    if File.exist?(logo_path)
      pdf.image logo_path, height: 20, at: [ 0, top ]
    else
      pdf.fill_color TEXT
      pdf.text_box "WAStays", size: 16, style: :bold, at: [ 0, top ]
    end

    pdf.fill_color TEXT
    pdf.text_box @hotel.name, size: 11, style: :bold, at: [ 0, top - 26 ], width: 300
    if @presenter.hotel_address_display.present?
      pdf.fill_color TEXT_MUTED
      pdf.text_box @presenter.hotel_address_display, size: 9, at: [ 0, top - 40 ], width: 300
    end

    box_width = 190
    box_left = pdf.bounds.width - box_width
    pdf.stroke_color BORDER
    pdf.line_width 0.5
    pdf.stroke_rectangle [ box_left, top ], box_width, 40
    pdf.fill_color TEXT_MUTED
    pdf.text_box "GUEST REGISTRATION CARD No.", at: [ box_left, top - 5 ], width: box_width, align: :center, size: 8, style: :bold
    pdf.fill_color TEXT
    pdf.text_box @booking.guest_registration_card_number_display, at: [ box_left, top - 22 ], width: box_width, align: :center, size: 12, style: :bold

    pdf.move_down 58
    pdf.stroke_color TEXT
    pdf.line_width 1
    pdf.stroke_horizontal_rule
    pdf.move_down 6
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
    pdf.fill_color TEXT
    if @presenter.terms&.dig("cancellation_policy").present?
      pdf.text "Cancellation Policy", size: 8, style: :bold
      pdf.move_down 2
      pdf.fill_color TEXT_MUTED
      pdf.text @presenter.terms["cancellation_policy"], size: 9, leading: 2
    else
      pdf.fill_color TEXT_MUTED
      pdf.text "Hotel terms are not configured.", size: 9
    end
    pdf.move_down 12
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

    if @card.signed? && @card.signature_data_url.present?
      signature_io = decode_signature(@card.signature_data_url)
      draw_signature_image(pdf, signature_io, at: [ box_left + 10, top - 26 ], height: 40) if signature_io
      pdf.fill_color TEXT_MUTED
      pdf.text_box "Signed by #{@card.signer_name} at #{l(@card.signed_at, format: :long)}",
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

  def draw_footer(pdf)
    pdf.stroke_color BORDER
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.move_down 6

    pdf.fill_color TEXT_MUTED
    pdf.text_box "Generated #{l(Time.current, format: :long)}", at: [ 0, pdf.cursor ], size: 8
    pdf.text_box "Page 1 of 1", at: [ pdf.bounds.width - 60, pdf.cursor ], width: 60, align: :right, size: 8
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
