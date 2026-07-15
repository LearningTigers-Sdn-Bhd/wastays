# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

class TourismTaxVoucherPdfService
  DARK_GREEN = "0a2e29"
  GOLD = "d9c5a0"
  WHITE = "ffffff"
  LIGHT_GRAY = "f9fafb"
  BORDER_GRAY = "e5e7eb"
  TEXT_PRIMARY = "111827"
  TEXT_MUTED = "6b7280"
  SUCCESS = "059669"
  WARNING = "d97706"

  def initialize(booking:, printed_by: nil)
    @booking = booking
    @hotel = booking.hotel
    @printed_by = printed_by
    @booking_rooms = booking.booking_rooms.includes(:room_type)
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: [ 40, 40, 40, 40 ],
      info: { Title: "Tourism Tax Voucher - #{@booking.formatted_tourism_tax_voucher_number}", Author: "WAStays", Creator: "WAStays", CreationDate: Time.current }
    )

    draw_page(pdf, "VOUCHER")
    pdf.start_new_page
    draw_page(pdf, "VOUCHER - DUPLICATE COPY")
    pdf.render
  end

  private

  def draw_page(pdf, title)
    draw_header(pdf, title)
    pdf.move_down 14
    draw_status_band(pdf)
    pdf.move_down 18
    draw_property(pdf)
    pdf.move_down 16
    draw_booking_details(pdf)
    pdf.move_down 16
    draw_particulars(pdf)
    pdf.move_down 16
    draw_signatures(pdf)
    pdf.move_down 22
    draw_footer(pdf)
  end

  def draw_header(pdf, title)
    logo_path = Rails.root.join("app/assets/images/logo/long-logo.png")
    File.exist?(logo_path) ? pdf.image(logo_path, height: 32) : (pdf.fill_color DARK_GREEN; pdf.text "WAStays", size: 22, style: :bold)
    pdf.move_up 32
    pdf.fill_color DARK_GREEN
    pdf.text title, size: 18, style: :bold, align: :right
    pdf.move_down 12
    pdf.stroke_color DARK_GREEN
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.line_width 1
  end

  def draw_status_band(pdf)
    pdf.fill_color @booking.tourism_tax_collected? ? SUCCESS : WARNING
    pdf.fill_rectangle [ 0, pdf.cursor ], 90, 18
    pdf.fill_color WHITE
    pdf.text_box @booking.tourism_tax_collected? ? "COLLECTED" : "PENDING", at: [ 0, pdf.cursor ], width: 90, height: 18, align: :center, valign: :center, size: 8, style: :bold
    pdf.move_down 28
    pdf.table(meta_rows, width: pdf.bounds.width)
  end

  def draw_property(pdf)
    section_band(pdf, "PROPERTY")
    pdf.move_down 8
    pdf.fill_color TEXT_PRIMARY
    pdf.text @hotel.name, size: 12, style: :bold
    pdf.fill_color TEXT_MUTED
    pdf.text [ @hotel.address, [ @hotel.city, @hotel.country ].compact.join(", ") ].compact_blank.join(" · "), size: 9
    pdf.text [ @hotel.contact_phone, @hotel.contact_email ].compact_blank.join(" · "), size: 9
  end

  def draw_booking_details(pdf)
    section_band(pdf, "BOOKING DETAILS")
    pdf.move_down 8
    pdf.table(detail_rows, width: pdf.bounds.width, column_widths: [ 64, pdf.bounds.width / 2 - 64, 78, pdf.bounds.width / 2 - 78 ])
  end

  def draw_particulars(pdf)
    quantity = [ @booking_rooms.size, 1 ].max
    rate = @booking.tourism_tax_total.to_d / quantity
    pdf.table(
      [
        [ { content: "PARTICULARS", colspan: 4, font_style: :bold, text_color: WHITE, background_color: DARK_GREEN, padding: [ 7, 8, 7, 8 ] } ],
        [ { content: "PARTICULARS", font_style: :bold, text_color: TEXT_MUTED }, { content: "QUANTITY", font_style: :bold, text_color: TEXT_MUTED }, { content: "RATE (MYR)", font_style: :bold, text_color: TEXT_MUTED }, { content: "AMOUNT (MYR)", font_style: :bold, text_color: TEXT_MUTED } ],
        [ { content: "Tourism Tax", text_color: TEXT_PRIMARY }, { content: quantity.to_s, text_color: TEXT_PRIMARY }, { content: fmt(rate), text_color: TEXT_PRIMARY }, { content: fmt(@booking.tourism_tax_total), text_color: TEXT_PRIMARY } ],
        [ { content: "TOTAL", colspan: 3, font_style: :bold, text_color: TEXT_PRIMARY, background_color: LIGHT_GRAY }, { content: fmt(@booking.tourism_tax_total), font_style: :bold, text_color: TEXT_PRIMARY, align: :right, background_color: LIGHT_GRAY } ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width * 0.52, 65, 85, pdf.bounds.width - (pdf.bounds.width * 0.52) - 150 ],
      cell_style: { border_color: BORDER_GRAY, padding: [ 7, 6, 7, 6 ], size: 9 }
    ) do |table|
      table.columns(1..3).align = :right
    end
  end

  def draw_signatures(pdf)
    pdf.stroke_color BORDER_GRAY
    section_band(pdf, "REMARKS & SIGNATURES")
    pdf.move_down 12
    pdf.fill_color TEXT_PRIMARY
    pdf.text "REMARK", size: 8, style: :bold
    pdf.move_down 8
    pdf.fill_color "64748b"
    pdf.text "." * 162, size: 7, character_spacing: 1.25
    pdf.move_down 18
    pdf.table([
      [ { content: "USER", font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [] }, { content: "", borders: [] }, { content: "", borders: [] } ],
      [ { content: @printed_by&.name.presence || "System", size: 10, text_color: TEXT_PRIMARY, borders: [], padding: [ 4, 0, 0, 0 ] }, { content: "", borders: [], padding: [ 4, 0, 0, 0 ] }, { content: "", borders: [], padding: [ 4, 0, 0, 0 ] } ],
      [ { content: "", borders: [ :bottom ], border_color: BORDER_GRAY }, { content: "", borders: [ :bottom ], border_color: BORDER_GRAY }, { content: "", borders: [ :bottom ], border_color: BORDER_GRAY } ],
      [ { content: "", borders: [] }, { content: "Guest Signature", size: 8, text_color: TEXT_MUTED, borders: [], align: :center }, { content: "Authorized Signatory", size: 8, text_color: TEXT_MUTED, borders: [], align: :center } ]
    ], width: pdf.bounds.width, column_widths: [ pdf.bounds.width * 0.42, pdf.bounds.width * 0.29, pdf.bounds.width * 0.29 ])
  end

  def draw_footer(pdf)
    pdf.stroke_color BORDER_GRAY
    pdf.stroke_horizontal_rule
    pdf.move_down 16
    pdf.fill_color TEXT_MUTED
    pdf.text footer_text, size: 9, align: :center, style: :italic
  end

  def meta_rows
    [
      [ { content: "VOUCHER NO.", font_style: :bold, text_color: GOLD, size: 8, borders: [] }, { content: "ENTERED ON", font_style: :bold, text_color: GOLD, size: 8, borders: [], align: :right } ],
      [ { content: @booking.formatted_tourism_tax_voucher_number || "Pending assignment", font_style: :bold, size: 12, text_color: TEXT_PRIMARY, borders: [] }, { content: Time.current.strftime("%Y/%m/%d %H:%M:%S"), size: 10, text_color: TEXT_PRIMARY, borders: [], align: :right } ]
    ]
  end

  def detail_rows
    [
      label_value_row("ROOM", room_labels, "GUEST", @booking.guest_name),
      label_value_row("FOLIO NO.", @booking.folio_account_reference_display.presence || "Not yet assigned", "POSTING DATE", posting_date_label)
    ]
  end

  def label_value_row(left_label, left_value, right_label, right_value)
    [
      { content: left_label, font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [] },
      { content: left_value, size: 10, text_color: TEXT_PRIMARY, borders: [ :bottom ], border_color: BORDER_GRAY },
      { content: right_label, font_style: :bold, size: 8, text_color: TEXT_MUTED, borders: [] },
      { content: right_value, size: 10, text_color: TEXT_PRIMARY, borders: [ :bottom ], border_color: BORDER_GRAY }
    ]
  end

  def room_labels
    return "Unassigned" if @booking_rooms.empty?

    @booking_rooms.map { |room| "#{room.room_type_snapshot["name"].presence || room.room_type.name} - #{room.room_number.presence || "Unassigned"}" }.join("\n")
  end

  def posting_date_label
    collection_date&.strftime("%d %B %Y") || "Pending collection"
  end

  def footer_text
    return "This voucher is to prove that the guest has paid the tourism fee." if @booking.tourism_tax_collected?

    "This voucher records the tourism fee payable for this stay."
  end

  def collection_date
    @booking.booking_folio&.folio_transactions&.payment
      &.where("metadata->>'source' = ?", "tourism_tax_check_in")&.first&.posting_date
  end

  def section_band(pdf, text)
    pdf.fill_color DARK_GREEN
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 20
    pdf.fill_color WHITE
    pdf.move_down 6
    pdf.indent(8) { pdf.text text, size: 8, style: :bold }
    pdf.move_down 14
  end

  def fmt(amount)
    format("%.2f", amount.to_f)
  end
end
