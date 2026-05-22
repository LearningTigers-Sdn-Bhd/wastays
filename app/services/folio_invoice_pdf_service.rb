# frozen_string_literal: true

require "prawn"
require "prawn/table"

Prawn::Fonts::AFM.hide_m17n_warning = true

# Generates a folio-sourced itemised invoice from a closed BookingFolio.
# Line items are derived from FolioTransaction records — not booking snapshot
# fields — giving a true day-by-day ledger view for the guest.
class FolioInvoicePdfService
  DARK_GREEN   = "0a2e29"
  GOLD         = "d9c5a0"
  WHITE        = "ffffff"
  LIGHT_GRAY   = "f9fafb"
  BORDER_GRAY  = "e5e7eb"
  TEXT_PRIMARY = "111827"
  TEXT_MUTED   = "6b7280"
  SUCCESS      = "059669"
  DANGER       = "dc2626"

  TRANSACTION_TYPE_LABELS = {
    "accommodation" => "Room Charge",
    "tax"           => "Tax",
    "fb"            => "Food & Beverage",
    "no_show_charge" => "No-Show Charge",
    "other"         => "Other Charge",
    "adjustment"    => "Adjustment",
    "correction"    => "Correction",
    "discount"      => "Discount",
    "write_off"     => "Write-Off",
    "gateway_payment" => "Payment",
    "cash"          => "Cash Payment",
    "refund"        => "Refund",
    "booking_payment" => "Booking Payment"
  }.freeze

  def initialize(booking)
    @booking = booking
    @hotel   = booking.hotel
    @folio   = booking.booking_folio
  end

  def generate
    pdf = Prawn::Document.new(
      page_size: "A4",
      margin: [ 40, 40, 40, 40 ],
      info: {
        Title:        "Folio Invoice - #{@booking.formatted_invoice_number || @booking.confirmation_token}",
        Author:       "WAStays",
        Creator:      "WAStays",
        CreationDate: Time.now
      }
    )

    draw_header(pdf)
    pdf.move_down 20
    draw_meta(pdf)
    pdf.move_down 30
    draw_parties(pdf)
    pdf.move_down 35
    draw_stay_summary(pdf)
    pdf.move_down 20
    draw_ledger(pdf)
    pdf.move_down 20
    draw_totals_band(pdf)
    pdf.move_down 30
    draw_footer(pdf)

    pdf.render
  end

  private

  # ──────────────────────────────────────────────
  # Header
  # ──────────────────────────────────────────────

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
    pdf.text "FOLIO INVOICE", size: 20, style: :bold, align: :right
    pdf.move_down 12
    pdf.stroke_color DARK_GREEN
    pdf.line_width 0.5
    pdf.stroke_horizontal_rule
    pdf.line_width 1
    pdf.fill_color TEXT_PRIMARY
  end

  # ──────────────────────────────────────────────
  # Meta block — invoice number, dates
  # ──────────────────────────────────────────────

  def draw_meta(pdf)
    issue_date   = (@booking.checked_out_at || @booking.check_out).strftime("%d %B %Y")
    invoice_ref  = @booking.formatted_invoice_number.presence || @booking.confirmation_token
    folio_ref    = @booking.formatted_folio_number.presence || "—"
    guest_reg    = @booking.formatted_guest_registration_number.presence || "—"

    pdf.table(
      [
        [
          { content: "INVOICE NUMBER",    font_style: :bold, text_color: GOLD, size: 8, borders: [] },
          { content: "FOLIO / REG. NO.",  font_style: :bold, text_color: GOLD, size: 8, borders: [], align: :center },
          { content: "ISSUE DATE",        font_style: :bold, text_color: GOLD, size: 8, borders: [], align: :right }
        ],
        [
          { content: invoice_ref,         font_style: :bold, size: 14, text_color: TEXT_PRIMARY, borders: [] },
          { content: "#{folio_ref}  ·  #{guest_reg}", size: 9, text_color: TEXT_MUTED, borders: [], align: :center },
          { content: issue_date,          size: 11, text_color: TEXT_PRIMARY, borders: [], align: :right }
        ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width * 0.4, pdf.bounds.width * 0.35, pdf.bounds.width * 0.25 ]
    )
  end

  # ──────────────────────────────────────────────
  # Parties — billed to / property
  # ──────────────────────────────────────────────

  def draw_parties(pdf)
    hotel_location = [ @hotel.address, @hotel.city, @hotel.country ].compact.reject(&:blank?).join(", ")

    pdf.table(
      [
        [
          { content: "BILLED TO", font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 6, 0 ] },
          { content: "PROPERTY",  font_style: :bold, text_color: GOLD, size: 8, borders: [], padding: [ 0, 0, 6, 0 ], align: :right }
        ],
        [
          { content: @booking.guest_name,  font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 2, 0 ] },
          { content: @hotel.name,          font_style: :bold, size: 11, text_color: TEXT_PRIMARY, borders: [], padding: [ 0, 0, 2, 0 ], align: :right }
        ],
        [
          { content: @booking.guest_email, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 1, 0 ] },
          { content: hotel_location,       size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 1, 0 ], align: :right }
        ],
        [
          { content: @booking.guest_phone, size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 0, 0 ] },
          { content: "",                   size: 9, text_color: TEXT_MUTED, borders: [], padding: [ 0, 0, 0, 0 ], align: :right }
        ]
      ],
      width: pdf.bounds.width,
      column_widths: [ pdf.bounds.width / 2, pdf.bounds.width / 2 ]
    )
  end

  # ──────────────────────────────────────────────
  # Stay summary band
  # ──────────────────────────────────────────────

  def draw_stay_summary(pdf)
    nights = ((@booking.check_out - @booking.check_in).to_i rescue 0)
    nights_label = nights == 1 ? "1 Night" : "#{nights} Nights"
    room_label   = @booking.booking_rooms.includes(:room_type).map { |br|
      [ br.room_type_snapshot["name"].presence || br.room_type&.name, br.room_number.presence ].compact.join(" · ")
    }.join(", ")

    pdf.fill_color LIGHT_GRAY
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, 26
    pdf.fill_color TEXT_PRIMARY
    pdf.move_down 8
    pdf.indent(12) do
      pdf.text "STAY: #{@booking.check_in.strftime('%d %b %Y')} — #{@booking.check_out.strftime('%d %b %Y')}  (#{nights_label})  ·  #{room_label}",
               size: 9, style: :bold
    end
    pdf.move_down 18
    pdf.fill_color TEXT_PRIMARY
  end

  # ──────────────────────────────────────────────
  # Ledger — chronological folio transactions
  # ──────────────────────────────────────────────

  def draw_ledger(pdf)
    transactions = @folio.folio_transactions.order(:posting_date, :created_at).to_a
    return if transactions.empty?

    desc_w = (pdf.bounds.width * 0.50).floor
    date_w = 72
    type_w = 90
    amt_w  = pdf.bounds.width - desc_w - date_w - type_w

    header_row = [
      { content: "DESCRIPTION",     font_style: :bold, size: 8, text_color: TEXT_MUTED },
      { content: "DATE",            font_style: :bold, size: 8, text_color: TEXT_MUTED },
      { content: "TYPE",            font_style: :bold, size: 8, text_color: TEXT_MUTED },
      { content: "AMOUNT",          font_style: :bold, size: 8, text_color: TEXT_MUTED, align: :right }
    ]

    data_rows = transactions.map do |txn|
      amount_str, amount_color = format_txn_amount(txn)
      [
        { content: txn.description.to_s,                   size: 9,  text_color: TEXT_PRIMARY },
        { content: txn.posting_date.strftime("%d %b %Y"),  size: 9,  text_color: TEXT_MUTED },
        { content: txn_label(txn),                         size: 8,  text_color: TEXT_MUTED },
        { content: amount_str,                             size: 9,  text_color: amount_color, align: :right }
      ]
    end

    pdf.table(
      [ header_row ] + data_rows,
      width: pdf.bounds.width,
      column_widths: [ desc_w, date_w, type_w, amt_w ],
      cell_style: { borders: [ :bottom ], padding: [ 10, 6, 10, 6 ], border_color: BORDER_GRAY }
    )
  end

  # ──────────────────────────────────────────────
  # Totals band
  # ──────────────────────────────────────────────

  def draw_totals_band(pdf)
    txns = @folio.folio_transactions.to_a

    total_charges     = txns.select(&:charge?).sum(&:amount).to_d
    total_adjustments = txns.select(&:adjustment?).sum(&:amount).to_d
    total_payments    = txns.select(&:payment?).sum { |t| t.amount.to_d.abs }
    net_balance       = @folio.outstanding_balance.to_d

    label_w = pdf.bounds.width * 0.75
    val_w   = pdf.bounds.width * 0.25

    summary_rows = [
      [ { content: "Total Charges",     size: 9, text_color: TEXT_PRIMARY, borders: [], align: :right },
        { content: "#{currency} #{fmt(total_charges)}",        size: 9, text_color: TEXT_PRIMARY, borders: [], align: :right } ],
      [ { content: "Total Adjustments", size: 9, text_color: TEXT_MUTED, borders: [], align: :right },
        { content: "#{currency} #{fmt(total_adjustments)}",    size: 9, text_color: TEXT_MUTED, borders: [], align: :right } ],
      [ { content: "Total Payments",    size: 9, text_color: SUCCESS, borders: [], align: :right },
        { content: "#{currency} (#{fmt(total_payments)})",     size: 9, text_color: SUCCESS, borders: [], align: :right } ]
    ]

    pdf.table(summary_rows, width: pdf.bounds.width, column_widths: [ label_w, val_w ])
    pdf.move_down 16

    band_h = 50
    balance_color = net_balance.zero? ? SUCCESS : DANGER
    pdf.fill_color DARK_GREEN
    pdf.fill_rectangle [ 0, pdf.cursor ], pdf.bounds.width, band_h
    pdf.fill_color WHITE
    pdf.draw_text "BALANCE DUE", at: [ 18, pdf.cursor - 30 ], size: 10, style: :bold
    balance_str = net_balance.zero? ? "SETTLED" : "#{currency} #{fmt(net_balance)}"
    pdf.text_box balance_str,
      at: [ 0, pdf.cursor ], width: pdf.bounds.width - 18, height: band_h,
      align: :right, valign: :center, size: 18, style: :bold
    pdf.move_down band_h + 10
    pdf.fill_color TEXT_PRIMARY
  end

  # ──────────────────────────────────────────────
  # Footer
  # ──────────────────────────────────────────────

  def draw_footer(pdf)
    pdf.stroke_color BORDER_GRAY
    pdf.stroke_horizontal_rule
    pdf.move_down 16
    pdf.fill_color TEXT_MUTED
    pdf.text "Thank you for staying with us. We hope to welcome you again soon!", size: 9, align: :center, style: :italic
    pdf.move_down 10
    pdf.text "This is a system-generated folio invoice. No signature required.", size: 8, align: :center
    pdf.text "WAStays · hello@wastays.com · www.wastays.com", size: 8, align: :center
  end

  # ──────────────────────────────────────────────
  # Helpers
  # ──────────────────────────────────────────────

  def txn_label(txn)
    TRANSACTION_TYPE_LABELS.fetch(txn.category, txn.category.to_s.humanize)
  end

  def format_txn_amount(txn)
    amt = txn.amount.to_d
    case txn.transaction_type
    when "charge"
      [ "#{currency} #{fmt(amt)}", TEXT_PRIMARY ]
    when "payment"
      # Payments are credits — shown in green with parentheses
      [ "#{currency} (#{fmt(amt.abs)})", SUCCESS ]
    when "adjustment"
      color = amt.negative? ? SUCCESS : TEXT_PRIMARY
      [ "#{currency} #{fmt(amt)}", color ]
    else
      [ "#{currency} #{fmt(amt)}", TEXT_PRIMARY ]
    end
  end

  def currency
    @currency ||= @booking.currency.presence || @hotel.default_currency.presence || "MYR"
  end

  def fmt(amount)
    format("%.2f", amount.to_f)
  end
end
