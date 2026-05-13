require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

class InvoicePdfService
  DARK_GREEN   = "0a2e29"
  GOLD         = "d9c5a0"
  WHITE        = "ffffff"
  LIGHT_GRAY   = "f9fafb"
  BORDER_GRAY  = "e5e7eb"
  TEXT_PRIMARY = "111827"
  TEXT_MUTED   = "6b7280"
  SUCCESS      = "059669"
  WARNING      = "d97706"

  def initialize(booking)
    @booking       = booking
    @hotel         = booking.hotel
    @nights        = (booking.check_out - booking.check_in).to_i
    @booking_rooms = booking.booking_rooms.includes(:room_type)
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: [ 40, 40, 40, 40 ],
      info: { Title: "Invoice - #{@booking.confirmation_token}", Author: "WAStays", Creator: "WAStays", CreationDate: Time.now }
    )

    draw_header(pdf)
    pdf.move_down 20
    draw_meta(pdf)
    pdf.move_down 30
    draw_parties(pdf)
    pdf.move_down 35
    draw_line_items(pdf)
    pdf.move_down 40
    draw_footer(pdf)

    pdf.render
  end

  private

  def draw_header(pdf)
    logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
    File.exist?(logo_path) ? pdf.image(logo_path, height: 32) : (pdf.fill_color DARK_GREEN; pdf.text "WAStays", size: 22, style: :bold)
    pdf.move_up 32
    pdf.fill_color DARK_GREEN
    pdf.text "INVOICE", size: 22, style: :bold, align: :right
    pdf.move_down 12
    pdf.stroke_color DARK_GREEN
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.line_width 1
  end

  def draw_meta(pdf)
    issue_date = (@booking.checked_out_at || @booking.check_out).strftime("%d %B %Y")

    pdf.fill_color TEXT_PRIMARY
    pdf.table([
      [ { content: "INVOICE NUMBER", font_style: :bold, text_color: GOLD, size: 8, borders: [] },
        { content: "ISSUE DATE", font_style: :bold, text_color: GOLD, size: 8, borders: [], align: :right } ],
      [ { content: @booking.confirmation_token, font_style: :bold, size: 14, text_color: TEXT_PRIMARY, borders: [] },
        { content: issue_date, size: 11, text_color: TEXT_PRIMARY, borders: [], align: :right } ]
    ], width: pdf.bounds.width)
  end

  def draw_parties(pdf)
    pdf.fill_color TEXT_PRIMARY
    hotel_location = [ @hotel.city, @hotel.country ].compact.join(", ")

    pdf.table([
      [ { content: "BILLED TO", font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 6, 0 ] },
        { content: "PROPERTY",  font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 6, 0 ], align: :right } ],
      [ { content: @booking.guest_name,  font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 2, 0 ] },
        { content: @hotel.name,          font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 2, 0 ], align: :right } ],
      [ { content: @booking.guest_email, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 1, 0 ] },
        { content: hotel_location,       size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 1, 0 ], align: :right } ],
      [ { content: @booking.guest_phone, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 0, 0 ] },
        { content: "", borders: [], padding: [ 0, 0, 0, 0 ] } ]
    ], width: pdf.bounds.width, column_widths: [ pdf.bounds.width / 2, pdf.bounds.width / 2 ])
  end

  def draw_line_items(pdf)
    nights_label = @nights == 1 ? "1 Night" : "#{@nights} Nights"

    pdf.fill_color LIGHT_GRAY
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 26
    pdf.fill_color TEXT_PRIMARY
    pdf.move_down 8
    pdf.indent(12) { pdf.text "STAY DETAILS: #{@booking.check_in.strftime('%d %b %Y')} — #{@booking.check_out.strftime('%d %b %Y')}  (#{nights_label})", size: 9, style: :bold }
    pdf.move_down 18

    desc_w   = (pdf.bounds.width * 0.55).floor
    qty_w    = 50
    nights_w = 60
    amt_w    = pdf.bounds.width - desc_w - qty_w - nights_w

    rows = @booking_rooms.map do |room|
      name = room.room_type_snapshot["name"].presence || room.room_type.name
      [ { content: name, size: 10, text_color: TEXT_PRIMARY },
        { content: room.quantity.to_s, size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: @nights.to_s, size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: "MYR #{fmt(room.subtotal)}", size: 10, text_color: TEXT_PRIMARY, align: :right } ]
    end

    tax_rows = Array(@booking.tax_lines).map do |tax|
      [ { content: tax["name"].to_s, size: 10, text_color: TEXT_MUTED, colspan: 3 },
        { content: "MYR #{fmt(tax["amount"])}", size: 10, text_color: TEXT_MUTED, align: :right } ]
    end

    pdf.table(
      [ [ { content: "DESCRIPTION", font_style: :bold, size: 8, text_color: TEXT_MUTED },
          { content: "QTY",      font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :center },
          { content: "NIGHTS",   font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :center },
          { content: "SUBTOTAL", font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :right } ] ] + rows + tax_rows,
      width: pdf.bounds.width,
      column_widths: [ desc_w, qty_w, nights_w, amt_w ],
      cell_style: { borders: [ :bottom ], padding: [ 12, 6, 12, 6 ], border_color: BORDER_GRAY }
    )

    pdf.move_down 30
    band_h = 54
    pdf.fill_color DARK_GREEN
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, band_h
    pdf.fill_color WHITE
    pdf.draw_text "TOTAL AMOUNT", at: [ 18, pdf.cursor - 32 ], size: 10, style: :bold
    pdf.text_box "MYR #{fmt(@booking.total_amount)}", at: [ 0, pdf.cursor ], width: pdf.bounds.width - 18, height: band_h, align: :right, valign: :center, size: 20, style: :bold
    pdf.move_down band_h + 40
    pdf.fill_color TEXT_PRIMARY
  end

  def draw_footer(pdf)
    pdf.stroke_color BORDER_GRAY
    pdf.stroke_horizontal_rule
    pdf.move_down 20
    pdf.fill_color TEXT_MUTED
    pdf.text "Thank you for staying with us. We hope to welcome you again soon!", size: 9, align: :center, style: :italic
    pdf.move_down 12
    pdf.text "This is a system-generated invoice. No signature required.", size: 8, align: :center
    pdf.text "WAStays · hello@wastays.com · www.wastays.com", size: 8, align: :center
  end

  def fmt(amount)
    format("%.2f", amount.to_f)
  end
end
