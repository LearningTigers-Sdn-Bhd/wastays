require "prawn"
require "prawn/table"
require "rqrcode"
require "stringio"

Prawn::Fonts::AFM.hide_m17n_warning = true

class EInvoicePdfService
  DARK_GREEN   = "0a2e29"
  GOLD         = "d9c5a0"
  WHITE        = "ffffff"
  LIGHT_GRAY   = "f9fafb"
  BORDER_GRAY  = "e5e7eb"
  TEXT_PRIMARY = "111827"
  TEXT_MUTED   = "6b7280"
  SUCCESS      = "059669"
  INFO_BG      = "f3f7ff"
  INFO_BORDER  = "d6e4ff"
  INFO_TEXT    = "1d4ed8"

  def initialize(booking, submission: nil)
    @booking = booking
    @hotel = booking.hotel
    @submission = submission || booking.ready_guest_e_invoice_submission
    @booking_rooms = booking.booking_rooms.includes(:room_type)
  end

  def generate
    raise ArgumentError, "Booking must have a valid guest e-invoice submission" unless @submission&.validated?

    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: [ 40, 40, 40, 40 ],
      info: {
        Title: "E-Invoice - #{@submission.internal_id || @booking.confirmation_token}",
        Author: "WAStays",
        Creator: "WAStays",
        CreationDate: Time.current
      }
    )

    draw_header(pdf)
    pdf.move_down 18
    draw_status_band(pdf)
    pdf.move_down 2
    draw_meta(pdf)
    pdf.move_down 26
    draw_parties(pdf)
    pdf.move_down 26
    draw_stay_summary(pdf)
    pdf.move_down 18
    draw_line_items(pdf)
    pdf.move_down 24
    draw_validation_panel(pdf)
    pdf.move_down 28
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
    pdf.text "E-INVOICE", size: 22, style: :bold, align: :right
    pdf.move_down 12
    pdf.stroke_color DARK_GREEN
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.line_width 1
    pdf.fill_color TEXT_PRIMARY
  end

  def draw_status_band(pdf)
    top = pdf.cursor
    badge_width = 124
    badge_height = 24
    pdf.fill_color SUCCESS
    pdf.rounded_rectangle [ 0, top ], badge_width, badge_height, 10
    pdf.fill
    pdf.fill_color WHITE
    pdf.bounding_box([ 0, top - 2 ], width: badge_width, height: badge_height) do
      pdf.move_down 6
      pdf.text "LHDN VALIDATED", align: :center, size: 9, style: :bold
    end
    pdf.fill_color TEXT_PRIMARY
    pdf.move_down badge_height
  end

  def draw_meta(pdf)
    issued_at = (@submission.submitted_at || @submission.validated_at || @booking.checked_out_at || @booking.check_out).strftime("%d %B %Y %H:%M")
    validated_at = @submission.validated_at&.strftime("%d %B %Y %H:%M") || "—"

    pdf.table(
      [
        [
          { content: "E-INVOICE NO.", font_style: :bold, text_color: GOLD, size: 8, borders: [] },
          { content: "LHDN TYPE", font_style: :bold, text_color: GOLD, size: 8, borders: [], align: :center },
          { content: "ISSUED AT", font_style: :bold, text_color: GOLD, size: 8, borders: [], align: :right }
        ],
        [
          { content: @submission.internal_id.presence || @booking.formatted_invoice_number || @booking.confirmation_token, font_style: :bold, size: 14, text_color: TEXT_PRIMARY, borders: [] },
          { content: @submission.document_type_label, size: 10, text_color: TEXT_PRIMARY, borders: [], align: :center },
          { content: issued_at, size: 10, text_color: TEXT_PRIMARY, borders: [], align: :right }
        ],
        [
          { content: "Booking #{@booking.confirmation_token}", size: 9, text_color: TEXT_MUTED, borders: [] },
          { content: @submission.document_scenario_label, size: 9, text_color: TEXT_MUTED, borders: [], align: :center },
          { content: "Validated #{validated_at}", size: 9, text_color: TEXT_MUTED, borders: [], align: :right }
        ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width * 0.42, pdf.bounds.width * 0.26, pdf.bounds.width * 0.32 ],
      cell_style: { borders: [], padding: [ 2, 0, 4, 0 ], valign: :top }
    ) do |table|
      table.row(0).padding = [ 0, 0, 6, 0 ]
      table.row(1).padding = [ 0, 0, 10, 0 ]
      table.row(2).padding = [ 0, 0, 0, 0 ]
    end
  end

  def draw_parties(pdf)
    supplier_location = [
      @hotel.address.presence,
      @hotel.city.presence,
      @hotel.country.presence
    ].compact.join(", ")

    buyer_address = [
      @booking.guest_home_address.presence,
      @booking.guest_city.presence,
      @booking.guest_country.presence
    ].compact.join(", ")

    pdf.table(
      [
        [
          { content: "ISSUED BY", font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 6, 0 ] },
          { content: "BILLED TO", font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 6, 0 ] }
        ],
        [
          { content: @submission.supplier_name.presence || @hotel.name, font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [] },
          { content: @booking.guest_name, font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [] }
        ],
        [
          { content: "TIN: #{@submission.supplier_tin.presence || '—'}", size: 9, text_color: TEXT_MUTED, borders: [] },
          { content: buyer_identity_line, size: 9, text_color: TEXT_MUTED, borders: [] }
        ],
        [
          { content: supplier_location, size: 9, text_color: TEXT_MUTED, borders: [] },
          { content: buyer_address.presence || @booking.guest_email.to_s, size: 9, text_color: TEXT_MUTED, borders: [] }
        ],
        [
          { content: "Stay property: #{@hotel.name}", size: 9, text_color: TEXT_MUTED, borders: [] },
          { content: @booking.guest_phone.to_s, size: 9, text_color: TEXT_MUTED, borders: [] }
        ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width / 2, pdf.bounds.width / 2 ]
    )
  end

  def draw_stay_summary(pdf)
    pdf.fill_color LIGHT_GRAY
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 26
    pdf.fill_color TEXT_PRIMARY
    pdf.move_down 8
    pdf.indent(12) do
      pdf.text stay_summary_text, size: 9, style: :bold
    end
    pdf.move_down 18
  end

  def draw_line_items(pdf)
    desc_w = (pdf.bounds.width * 0.55).floor
    qty_w = 50
    nights_w = 60
    amt_w = pdf.bounds.width - desc_w - qty_w - nights_w

    rows = line_item_rows
    tax_rows = adjustment_submission? ? [] : tax_line_rows

    pdf.table(
      [
        [
          { content: "DESCRIPTION", font_style: :bold, size: 8, text_color: TEXT_MUTED },
          { content: "QTY", font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :center },
          { content: "NIGHTS", font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :center },
          { content: "SUBTOTAL", font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :right }
        ]
      ] + rows + tax_rows,
      width: pdf.bounds.width,
      column_widths: [ desc_w, qty_w, nights_w, amt_w ],
      cell_style: { borders: [ :bottom ], padding: [ 12, 6, 12, 6 ], border_color: BORDER_GRAY }
    )

    pdf.move_down 18
    band_h = 54
    pdf.fill_color DARK_GREEN
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, band_h
    pdf.fill_color WHITE
    pdf.draw_text total_label, at: [ 18, pdf.cursor - 32 ], size: 10, style: :bold
    pdf.text_box "MYR #{fmt(pdf_total_amount)}", at: [ 0, pdf.cursor ], width: pdf.bounds.width - 18, height: band_h, align: :right, valign: :center, size: 20, style: :bold
    pdf.move_down band_h + 12
    pdf.fill_color TEXT_PRIMARY
  end

  def draw_validation_panel(pdf)
    panel_top = pdf.cursor
    panel_height = 176

    pdf.stroke_color BORDER_GRAY
    pdf.fill_color LIGHT_GRAY
    pdf.rounded_rectangle [ 0, panel_top ], pdf.bounds.width, panel_height, 12
    pdf.fill_and_stroke
    pdf.fill_color TEXT_PRIMARY

    qr_block_width = 132
    left_width = pdf.bounds.width - qr_block_width - 42

    pdf.bounding_box([ 18, panel_top - 16 ], width: left_width, height: panel_height - 24) do
      pdf.text "LHDN Validation Details", size: 11, style: :bold
      pdf.move_down 10

      pdf.table(
        [
          [ "LHDN UUID", @submission.uuid.to_s ],
          [ "Submission UID", @submission.submission_uid.to_s ],
          [ "Issued status", "Validated by LHDN MyInvois" ]
        ],
        width: left_width,
        cell_style: {
          borders: [],
          padding: [ 4, 0, 4, 0 ],
          size: 9,
          text_color: TEXT_PRIMARY
        },
        column_widths: [ 104, left_width - 104 ]
      ) do |table|
        table.column(0).font_style = :bold
        table.column(0).text_color = TEXT_MUTED
      end

      if @submission.validation_url.present?
        pdf.move_down 12
        info_top = pdf.cursor
        pdf.fill_color INFO_BG
        pdf.stroke_color INFO_BORDER
        pdf.rounded_rectangle [ 0, info_top ], left_width, 58, 10
        pdf.fill_and_stroke

        pdf.bounding_box([ 12, info_top - 11 ], width: left_width - 24, height: 42) do
          pdf.fill_color INFO_TEXT
          pdf.text "Verification Link", size: 8, style: :bold
          pdf.move_down 5
          pdf.fill_color TEXT_PRIMARY
          pdf.formatted_text_box [
            { text: @submission.validation_url.to_s, color: TEXT_PRIMARY, size: 7.5 }
          ], at: [ 0, pdf.cursor ], width: left_width - 24, height: 32, overflow: :shrink_to_fit
        end
      end
    end

    if @submission.validation_url.present?
      qr_png = validation_qr_png
      qr_box_left = pdf.bounds.width - qr_block_width + 2
      qr_box_width = 112
      qr_box_height = 122
      pdf.fill_color WHITE
      pdf.stroke_color BORDER_GRAY
      pdf.rounded_rectangle [ qr_box_left, panel_top - 16 ], qr_box_width, qr_box_height, 14
      pdf.fill_and_stroke
      pdf.image StringIO.new(qr_png), at: [ qr_box_left + 16, panel_top - 26 ], width: 80, height: 80
      pdf.fill_color TEXT_MUTED
      pdf.text_box "Scan to verify on\nMyInvois", at: [ qr_box_left + 10, panel_top - 104 ], width: qr_box_width - 20, height: 26, align: :center, valign: :center, size: 8
    end

    pdf.move_down panel_height + 4
    pdf.fill_color TEXT_PRIMARY
  end

  def draw_footer(pdf)
    pdf.stroke_color BORDER_GRAY
    pdf.stroke_horizontal_rule
    pdf.move_down 16
    pdf.fill_color TEXT_MUTED
    pdf.text "This is a system-generated e-invoice validated by LHDN MyInvois. No signature required.", size: 8, align: :center
    pdf.move_down 6
    pdf.text "Use QR code or validation link to verify this document with LHDN.", size: 8, align: :center
    pdf.text "WAStays · hello@wastays.com · www.wastays.com", size: 8, align: :center
  end

  def buyer_identity_line
    label = @booking.guest_document_type.to_s == "ic" ? "IC" : "Passport"
    identifier = @booking.guest_government_id.presence || "—"
    "ID: #{label} #{identifier}"
  end

  def validation_qr_png
    RQRCode::QRCode.new(@submission.validation_url).as_png(size: 220, border_modules: 1).to_s
  end

  def fmt(amount)
    format("%.2f", amount.to_f)
  end

  def adjustment_submission?
    @submission.adjustment?
  end

  def stay_summary_text
    if adjustment_submission?
      "ADJUSTMENT FOR STAY: #{@booking.check_in.strftime('%d %b %Y')} — #{@booking.check_out.strftime('%d %b %Y')}"
    else
      nights = [ (@booking.check_out.to_date - @booking.check_in.to_date).to_i, 1 ].max
      nights_label = nights == 1 ? "1 Night" : "#{nights} Nights"
      "STAY DETAILS: #{@booking.check_in.strftime('%d %b %Y')} — #{@booking.check_out.strftime('%d %b %Y')}  (#{nights_label})"
    end
  end

  def line_item_rows
    return adjustment_line_item_rows if adjustment_submission?

    @booking_rooms.map do |room|
      room_name = room.room_type_snapshot["name"].presence || room.room_type&.name || "Room"
      nights = [ ((@booking.check_out.to_date - @booking.check_in.to_date).to_i), 1 ].max

      [
        { content: room_name, size: 10, text_color: TEXT_PRIMARY },
        { content: room.quantity.to_s, size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: nights.to_s, size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: "MYR #{fmt(room.subtotal)}", size: 10, text_color: TEXT_PRIMARY, align: :right }
      ]
    end
  end

  def adjustment_line_item_rows
    [
      [
        { content: adjustment_description, size: 10, text_color: TEXT_PRIMARY },
        { content: "1", size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: "-", size: 10, text_color: TEXT_PRIMARY, align: :center },
        { content: "MYR #{fmt(adjustment_amount)}", size: 10, text_color: TEXT_PRIMARY, align: :right }
      ]
    ]
  end

  def tax_line_rows
    Array(@booking.tax_lines).map do |tax|
      [
        { content: tax["name"].to_s, size: 10, text_color: TEXT_MUTED, colspan: 3 },
        { content: "MYR #{fmt(tax["amount"])}", size: 10, text_color: TEXT_MUTED, align: :right }
      ]
    end
  end

  def total_label
    adjustment_submission? ? "ADJUSTMENT TOTAL" : "VALIDATED TOTAL"
  end

  def pdf_total_amount
    adjustment_submission? ? adjustment_amount : @booking.total_amount
  end

  def adjustment_amount
    @adjustment_amount ||= begin
      original = @booking.e_invoice_submissions
                         .guest_facing
                         .valid
                         .where(document_type: "01")
                         .find_by(internal_id: @submission.original_invoice_internal_id)

      original_total = original&.raw_response&.dig("acceptedDocuments", 0, "totalExcludingTax") ||
                       original&.raw_response&.dig("acceptedDocuments", 0, "totalIncludingTax") ||
                       @booking.total_amount
      folio_total = @booking.booking_folio&.total_charges.to_d.to_f + @booking.booking_folio&.total_adjustments.to_d.to_f

      (folio_total - original_total.to_d).abs
    end
  end

  def adjustment_description
    @submission.document_type == "03" ? "Additional charges adjustment" : "Refund/credit adjustment"
  end
end
