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
      margin: [ 28, 36, 24, 36 ],
      info: {
        Title: "E-Invoice - #{@submission.internal_id || @booking.confirmation_token}",
        Author: "WAStays",
        Creator: "WAStays",
        CreationDate: Time.current
      }
    )

    draw_header(pdf)
    pdf.move_down 10
    draw_status_band(pdf)
    pdf.move_down 2
    draw_meta(pdf)
    pdf.move_down 12
    draw_parties(pdf)
    pdf.move_down 12
    draw_stay_summary(pdf)
    pdf.move_down 10
    draw_line_items(pdf)
    pdf.move_down 12
    draw_validation_panel(pdf)
    pdf.move_down 10
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
    # hold_position: without it, bounding_box already advances the document
    # cursor to its own bottom edge - the move_down below was then double
    # counting the badge's height, which is what made this gap look huge.
    pdf.bounding_box([ 0, top - 2 ], width: badge_width, height: badge_height, hold_position: true) do
      pdf.move_down 6
      pdf.text "LHDN VALIDATED", align: :center, size: 9, style: :bold
    end
    pdf.fill_color TEXT_PRIMARY

    qr_height = @submission.validation_url.present? ? draw_top_left_qr(pdf, top, badge_width) : 0

    pdf.move_down [ badge_height, qr_height ].max
  end

  # Front and center, top-left, next to the status badge - not buried at the
  # bottom of the LHDN Validation Details panel - so whoever is holding the
  # printed page can scan it immediately rather than hunting for it. Sized to
  # actually be scannable on a printed page (a QR much smaller than this is
  # hard for a phone camera to focus on and decode), which is why it's taller
  # than the badge next to it - the caller advances the cursor by whichever
  # of the two is taller.
  def draw_top_left_qr(pdf, top, badge_width)
    qr_size = 56
    qr_left = badge_width + 14
    qr_png = validation_qr_png

    pdf.fill_color WHITE
    pdf.stroke_color BORDER_GRAY
    pdf.rounded_rectangle [ qr_left, top ], qr_size, qr_size, 8
    pdf.fill_and_stroke
    pdf.image StringIO.new(qr_png), at: [ qr_left + 4, top - 4 ], width: qr_size - 8, height: qr_size - 8

    pdf.fill_color TEXT_MUTED
    pdf.text_box "Scan to verify\non MyInvois", at: [ qr_left + qr_size + 10, top - (qr_size / 2) + 8 ], width: 90, height: 24, size: 7.5, valign: :center
    pdf.fill_color TEXT_PRIMARY

    qr_size
  end

  # Issued and validated happen within seconds of each other in real use (this
  # only submits a document once it is already accepted), so showing both was
  # redundant - just the one that matters legally, the issue date.
  def draw_meta(pdf)
    issued_at = (@submission.submitted_at || @submission.validated_at || @booking.checked_out_at || @booking.check_out).strftime("%d %B %Y %H:%M")

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
        ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width * 0.42, pdf.bounds.width * 0.26, pdf.bounds.width * 0.32 ],
      cell_style: { borders: [], padding: [ 2, 0, 3, 0 ], valign: :top }
    ) do |table|
      table.row(0).padding = [ 0, 0, 4, 0 ]
      table.row(1).padding = [ 0, 0, 0, 0 ]
    end
  end

  def draw_parties(pdf)
    supplier_location = [
      @hotel.address.presence,
      @hotel.city.presence,
      @hotel.country.presence
    ].compact.join(", ")

    buyer_address = buyer_address_presenter.display

    pdf.table(
      [
        [
          { content: "ISSUED BY", font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 4, 0 ] },
          { content: "BILLED TO", font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 4, 0 ] }
        ],
        [
          { content: @submission.supplier_name.presence || @hotel.name, font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [] },
          { content: buyer_value("name", @booking.guest_name), font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [] }
        ],
        [
          { content: "TIN: #{@submission.supplier_tin.presence || '—'}", size: 9, text_color: TEXT_MUTED, borders: [] },
          { content: buyer_identity_line, size: 9, text_color: TEXT_MUTED, borders: [] }
        ],
        [
          { content: supplier_location, size: 9, text_color: TEXT_MUTED, borders: [] },
          { content: buyer_address.presence || "Not provided", size: 9, text_color: TEXT_MUTED, borders: [] }
        ],
        [
          { content: "", borders: [] },
          { content: "#{buyer_value('contact_email', @booking.guest_email)}\n#{buyer_value('contact_phone', @booking.guest_phone)}\nBooking #{@booking.confirmation_token}", size: 9, text_color: TEXT_MUTED, borders: [] }
        ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width / 2, pdf.bounds.width / 2 ],
      cell_style: { padding: [ 2, 0, 2, 0 ] }
    )
  end

  def draw_stay_summary(pdf)
    pdf.fill_color LIGHT_GRAY
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 22
    pdf.fill_color TEXT_PRIMARY
    pdf.move_down 7
    pdf.indent(12) do
      pdf.text stay_summary_text, size: 9, style: :bold
    end
    pdf.move_down 12
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
      cell_style: { borders: [ :bottom ], padding: [ 8, 6, 8, 6 ], border_color: BORDER_GRAY }
    )

    pdf.move_down 12
    band_h = 44
    pdf.fill_color DARK_GREEN
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, band_h
    pdf.fill_color WHITE
    pdf.draw_text total_label, at: [ 18, pdf.cursor - 27 ], size: 10, style: :bold
    pdf.text_box "MYR #{fmt(pdf_total_amount)}", at: [ 0, pdf.cursor ], width: pdf.bounds.width - 18, height: band_h, align: :right, valign: :center, size: 20, style: :bold
    pdf.move_down band_h + 8
    pdf.fill_color TEXT_PRIMARY
  end

  # The QR code itself now lives top-left next to the status badge (see
  # draw_top_left_qr) so it's the first thing a reader sees, not buried down
  # here - this panel keeps the verification link as text for anyone who
  # can't scan but can click.
  def draw_validation_panel(pdf)
    panel_top = pdf.cursor
    panel_height = 130

    pdf.stroke_color BORDER_GRAY
    pdf.fill_color LIGHT_GRAY
    pdf.rounded_rectangle [ 0, panel_top ], pdf.bounds.width, panel_height, 12
    pdf.fill_and_stroke
    pdf.fill_color TEXT_PRIMARY

    left_width = pdf.bounds.width - 36

    pdf.bounding_box([ 18, panel_top - 14 ], width: left_width, height: panel_height - 20) do
      pdf.text "LHDN Validation Details", size: 11, style: :bold
      pdf.move_down 8

      pdf.table(
        [
          [ "LHDN UUID", @submission.uuid.to_s ],
          [ "Submission UID", @submission.submission_uid.to_s ],
          [ "Issued status", "Validated by LHDN MyInvois" ]
        ],
        width: left_width,
        cell_style: {
          borders: [],
          padding: [ 3, 0, 3, 0 ],
          size: 9,
          text_color: TEXT_PRIMARY
        },
        column_widths: [ 104, left_width - 104 ]
      ) do |table|
        table.column(0).font_style = :bold
        table.column(0).text_color = TEXT_MUTED
      end

      if @submission.validation_url.present?
        pdf.move_down 9
        info_top = pdf.cursor
        pdf.fill_color INFO_BG
        pdf.stroke_color INFO_BORDER
        pdf.rounded_rectangle [ 0, info_top ], left_width, 50, 10
        pdf.fill_and_stroke

        pdf.bounding_box([ 12, info_top - 10 ], width: left_width - 24, height: 36) do
          pdf.fill_color INFO_TEXT
          pdf.text "Verification Link", size: 8, style: :bold
          pdf.move_down 4
          pdf.fill_color TEXT_PRIMARY
          pdf.formatted_text_box [
            { text: @submission.validation_url.to_s, color: TEXT_PRIMARY, size: 7.5 }
          ], at: [ 0, pdf.cursor ], width: left_width - 24, height: 28, overflow: :shrink_to_fit
        end
      end
    end

    pdf.move_down panel_height + 4
    pdf.fill_color TEXT_PRIMARY
  end

  def draw_footer(pdf)
    pdf.stroke_color BORDER_GRAY
    pdf.stroke_horizontal_rule
    pdf.move_down 10
    pdf.fill_color TEXT_MUTED
    pdf.text "This is a system-generated e-invoice validated by LHDN MyInvois. No signature required.", size: 8, align: :center
    pdf.move_down 4
    pdf.text "WAStays · hello@wastays.com · www.wastays.com", size: 8, align: :center
  end

  def buyer_identity_line
    identity = EInvoice::GuestIdentityResolver.for_booking(@booking)
    label = buyer_value("document_type", identity.document_type).to_s == "ic" ? "MyKad" : "Passport"
    identifier = buyer_value("government_id", identity.document_number).presence || "—"
    "ID: #{label} #{identifier}"
  end

  def buyer_snapshot
    @buyer_snapshot ||= @submission.buyer_snapshot.to_h.stringify_keys
  end

  def buyer_value(key, fallback = nil)
    buyer_snapshot[key].presence || fallback
  end

  def buyer_address_presenter
    @buyer_address_presenter ||= if buyer_snapshot["billing_address"].present?
      PostalAddresses::Presenter.from_snapshot(buyer_snapshot["billing_address"])
    else
      PostalAddresses::Presenter.from_booking(@booking)
    end
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
        { content: "1", size: 10, text_color: TEXT_PRIMARY, align: :center },
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
