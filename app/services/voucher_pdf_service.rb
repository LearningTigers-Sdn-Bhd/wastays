require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

class VoucherPdfService
  DARK_GREEN   = "0a2e29"
  GOLD         = "d9c5a0"
  WHITE        = "ffffff"
  LIGHT_GRAY   = "f9fafb"
  BORDER_GRAY  = "e5e7eb"
  TEXT_PRIMARY = "111827"
  TEXT_MUTED   = "6b7280"
  SUCCESS      = "059669"

  def initialize(booking)
    @booking      = booking
    @hotel        = booking.hotel
    @nights       = (booking.check_out.to_date - booking.check_in.to_date).to_i
    @booking_rooms = booking.booking_rooms.includes(:room_type)
    @snapshot     = booking.hotel_snapshot || {}
    @policy       = @snapshot["property_policy"] || {}
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: [ 40, 40, 40, 40 ],
      info: {
        Title: "Booking Voucher - #{@booking.confirmation_token}",
        Author: "WAStays",
        Creator: "WAStays",
        CreationDate: Time.now
      }
    )

    draw_header(pdf)
    pdf.move_down 20
    draw_confirmation_band(pdf)
    pdf.move_down 24
    draw_property_section(pdf)
    pdf.move_down 24
    draw_stay_dates(pdf)
    pdf.move_down 24
    draw_rooms(pdf)
    pdf.move_down 24
    draw_guest_and_payment(pdf)
    pdf.move_down 24
    draw_special_requests(pdf)
    pdf.move_down 24
    draw_policies(pdf)
    pdf.move_down 30
    draw_footer(pdf)

    pdf.render
  end

  private

  def draw_header(pdf)
    logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")

    if File.exist?(logo_path)
      pdf.image logo_path, height: 32
    else
      pdf.fill_color DARK_GREEN
      pdf.text "WAStays", size: 22, style: :bold
    end

    pdf.move_up 32
    pdf.fill_color DARK_GREEN
    pdf.text "BOOKING VOUCHER", size: 22, style: :bold, align: :right

    pdf.move_down 12
    pdf.stroke_color DARK_GREEN
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.line_width 1
  end

  def draw_confirmation_band(pdf)
    qr_size   = 80
    band_height = [ qr_size + 20, 52 ].max

    pdf.fill_color DARK_GREEN
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, band_height

    pdf.fill_color GOLD
    pdf.draw_text "CONFIRMED", at: [ 18, pdf.cursor - 18 ], size: 9, style: :bold

    pdf.fill_color WHITE
    pdf.text_box @booking.confirmation_token,
      at: [ 18, pdf.cursor - 30 ],
      width: pdf.bounds.width - qr_size - 36,
      height: band_height - 30,
      valign: :center,
      size: 18,
      style: :bold

    qr_png = qr_image_io(@booking.confirmation_token)
    pdf.image qr_png,
      at: [ pdf.bounds.width - qr_size - 12, pdf.cursor - 10 ],
      width: qr_size,
      height: qr_size

    pdf.move_down band_height
  end

  def draw_property_section(pdf)
    section_label(pdf, "PROPERTY")
    pdf.move_down 8

    data = [
      [
        { content: @hotel.name, font_style: :bold, size: 14, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 2, 0 ] },
        { content: "Check-in Time",  font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 2, 0 ], align: :right }
      ],
      [
        { content: [ @hotel.city, @hotel.country ].compact.join(", "), size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 0, 0 ] },
        { content: @policy.fetch("check_in_time", "2:00 PM"), font_style: :bold, size: 10, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 0, 0 ], align: :right }
      ]
    ]
    pdf.table(data, width: pdf.bounds.width)
  end

  def draw_stay_dates(pdf)
    section_label(pdf, "STAY DETAILS")
    pdf.move_down 8

    nights_label = @nights == 1 ? "1 Night" : "#{@nights} Nights"
    adults_label = @booking.adults == 1 ? "1 Adult" : "#{@booking.adults} Adults"
    guests_label = @booking.children > 0 ? "#{adults_label}, #{@booking.children} Child#{@booking.children != 1 ? 'ren' : ''}" : adults_label

    w     = pdf.bounds.width
    col_w = (w / 4.0).floor
    last_col_w = w - (col_w * 3)
    data = [
      [
        { content: "CHECK-IN",   font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 4, 0 ] },
        { content: "CHECK-OUT",  font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 4, 0 ] },
        { content: "DURATION",   font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 4, 0 ] },
        { content: "GUESTS",     font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 4, 0 ] }
      ],
      [
        { content: @booking.check_in.strftime("%d %b %Y"),  font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 0, 0 ] },
        { content: @booking.check_out.strftime("%d %b %Y"), font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 0, 0 ] },
        { content: nights_label, font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 0, 0 ] },
        { content: guests_label, font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 0, 0 ] }
      ]
    ]
    pdf.table(data, width: w, column_widths: [ col_w, col_w, col_w, last_col_w ])
  end

  def draw_rooms(pdf)
    section_label(pdf, "ACCOMMODATION")
    pdf.move_down 8

    header_row = [
      { content: "ROOM TYPE",  font_style: :bold, size: 8, text_color: TEXT_MUTED },
      { content: "QTY",        font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :center },
      { content: "STATUS",     font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :right }
    ]

    desc_w   = (pdf.bounds.width * 0.7).floor
    qty_w    = 50
    status_w = pdf.bounds.width - desc_w - qty_w

    room_rows = @booking_rooms.map do |room|
      name = room.room_type_snapshot["name"].presence || room.room_type.name
      [
        { content: name,               size: 10, text_color: TEXT_PRIMARY },
        { content: room.quantity.to_s, size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: "PAID",             size: 9,  text_color: SUCCESS, font_style: :bold, align: :right }
      ]
    end

    pdf.table(
      [ header_row ] + room_rows,
      width: pdf.bounds.width,
      column_widths: [ desc_w, qty_w, status_w ],
      cell_style: { borders: [ :bottom ], padding: [ 10, 6, 10, 6 ], border_color: BORDER_GRAY }
    )
  end

  def draw_guest_and_payment(pdf)
    w    = pdf.bounds.width
    half = (w / 2.0).floor

    data = [
      [
        { content: "PRIMARY GUEST", font_style: :bold, size: 8, text_color: GOLD, borders: [], padding: [ 0, 12, 6, 0 ] },
        { content: "TOTAL PAID",    font_style: :bold, size: 8, text_color: GOLD, borders: [], padding: [ 0, 0, 6, 12 ] }
      ],
      [
        { content: @booking.guest_name,  font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 12, 2, 0 ] },
        { content: "MYR #{fmt(@booking.total_amount)}", font_style: :bold, size: 16, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 2, 12 ] }
      ],
      [
        { content: @booking.guest_email, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 12, 1, 0 ] },
        { content: "Payment confirmed", size: 8, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 1, 12 ] }
      ],
      [
        { content: @booking.guest_phone, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 12, 0, 0 ] },
        { content: "", borders: [], padding: [ 0, 0, 0, 12 ] }
      ]
    ]

    pdf.fill_color LIGHT_GRAY
    row_height = 90
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, row_height

    pdf.table(data, width: w, column_widths: [ half, w - half ])
  end

  def draw_special_requests(pdf)
    return if @booking.special_requests.blank?

    section_label(pdf, "SPECIAL REQUESTS")
    pdf.move_down 8

    pdf.fill_color TEXT_PRIMARY
    pdf.text @booking.special_requests, size: 9, leading: 2
  end

  def draw_policies(pdf)
    cancellation = @policy["cancellation_policy"]
    return unless cancellation.present?

    pdf.move_down 8
    section_label(pdf, "PROPERTY POLICIES")
    pdf.move_down 8

    pdf.fill_color TEXT_MUTED
    pdf.text "• Identification required upon check-in. Local government taxes may apply.", size: 8
    pdf.move_down 4
    pdf.text "• #{cancellation}", size: 8
  end

  def draw_footer(pdf)
    pdf.stroke_color BORDER_GRAY
    pdf.stroke_horizontal_rule
    pdf.move_down 14

    pdf.fill_color TEXT_MUTED
    pdf.text "Please present this voucher at check-in. This is an electronically generated document — no signature required.", size: 8, align: :center, style: :italic
    pdf.move_down 8
    pdf.text "WAStays · hello@wastays.com · www.wastays.com", size: 8, align: :center
  end

  def section_label(pdf, text)
    pdf.fill_color LIGHT_GRAY
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 20
    pdf.fill_color TEXT_MUTED
    pdf.move_down 6
    pdf.indent(8) { pdf.text text, size: 8, style: :bold }
    pdf.move_down 14
  end

  def qr_image_io(token)
    png = RQRCode::QRCode.new(token).as_png(
      bit_depth: 1,
      border_modules: 2,
      color_mode: ChunkyPNG::COLOR_GRAYSCALE,
      color: "black",
      file: nil,
      fill: "white",
      module_px_size: 6,
      resize_exactly_to: false,
      resize_gte_to: false
    )
    StringIO.new(png.to_s)
  end

  def fmt(amount)
    format("%.2f", amount.to_f)
  end
end
