# frozen_string_literal: true

require "prawn"

# Wears the shared print design system (DESIGN.md §12). The receipt draws its own
# body rather than going through PdfReportBuilder: it has no report tables, and its
# one number belongs on the stat strip.
class PaymentReceiptPdfService
  THEME = HotelPortal::Reports::Exports::PdfTheme

  def initialize(receipt)
    @receipt = receipt
    @hotel = receipt.hotel
    @presentation = Receipts::Presentation.new(receipt)
  end

  def generate
    pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
    THEME.configure_font(pdf)
    frame = HotelPortal::Reports::Exports::PdfReportFrame.new(
      pdf: pdf,
      hotel: @hotel,
      # The number is the title; the eyebrow says what the number belongs to.
      eyebrow: @presentation.title,
      report_name: @receipt.public_number,
      # Party blocks carry the payer and its address, so the strip stays empty.
      metadata: [],
      # Goes to the payer, not into the hotel's filing cabinet.
      confidential: false
    )

    frame.draw_header
    draw_void_notice(pdf) if @receipt.voided?
    HotelPortal::Reports::Exports::PdfPartyBlocks.new(pdf: pdf).draw(party_blocks)
    HotelPortal::Reports::Exports::PdfStatStrip.new(pdf: pdf).draw([ [ @presentation.amount_label, amount_label ] ])
    draw_note(pdf)
    frame.stamp_page_furniture
    pdf.render
  end

  private

  def document_info
    { Title: "#{@presentation.title} - #{@receipt.public_number}", Author: "WAStays", Creator: "WAStays", CreationDate: Time.current }
  end

  # A voided receipt reads exactly like a valid one at a glance, so the void has to
  # arrive before the amount does.
  def draw_void_notice(pdf)
    HotelPortal::Reports::Exports::PdfNoticeBand.new(pdf: pdf)
      .draw(label: "VOIDED", note: @presentation.void_note, variant: :danger)
  end

  def draw_note(pdf)
    pdf.fill_color THEME::COLORS[:muted]
    pdf.text @presentation.note, size: THEME::TYPE[:micro]
    pdf.fill_color THEME::COLORS[:ink]
  end

  # Three blocks rather than one metadata strip: a payer has an address, and an address
  # needs its own lines. The strip holds one short value per label, so it cannot carry one.
  # Blank entries are dropped by the block, so a fact nobody captured costs a line.
  def party_blocks
    [
      {
        heading: "Payer details",
        entries: [
          [ "Payer", payer_name ],
          [ "Address", payer_address ]
        ]
      },
      {
        heading: "Contact details",
        entries: [
          [ "Email", payer_value("email") ],
          [ "Phone", payer_value("phone") ]
        ]
      },
      {
        heading: "Payment details",
        entries: [
          [ "Received", THEME.format_time(@receipt.received_at, @hotel.hotel_time_zone) ],
          [ "Payment method", @receipt.payment_method.to_s.humanize ],
          [ "Reference", @receipt.external_reference ],
          { columns: [ [ "Booking no.", booking_number ],
                       [ "Confirmation", @receipt.context_snapshot.to_h["booking_confirmation_token"] ] ] }
        ]
      }
    ]
  end

  def amount_label = "#{@receipt.currency} #{THEME.money(@receipt.amount)}"

  def payer_name = payer_value("name").presence || "Not provided"

  def payer_value(key) = @receipt.payer_snapshot.to_h[key]

  # The confirmation token is frozen on the receipt; the booking number is not stored
  # there, so it is read from the booking the receipt names.
  def booking_number = receipt_booking&.formatted_reservation_number

  def receipt_booking
    return @receipt_booking if defined?(@receipt_booking)

    booking_id = @receipt.context_snapshot.to_h["booking_id"]
    @receipt_booking = booking_id.present? ? Booking.includes(:booking_guests).find_by(id: booking_id) : nil
  end

  # The guest record wins, so correcting an address reaches every reprint. The
  # issue-time snapshot answers only when the booking is gone.
  def payer_address
    live_payer_address.presence || frozen_payer_address.presence || "Not provided"
  end

  def live_payer_address
    booking = receipt_booking
    return if booking.blank?

    PostalAddresses::Presenter.from_booking_guest(
      booking.booking_guests.find(&:primary?),
      fallback_booking: booking
    ).display
  end

  def frozen_payer_address
    address = payer_value("billing_address")
    return if address.blank?

    PostalAddresses::Presenter.from_snapshot(address).display
  end
end
