# frozen_string_literal: true

require "prawn"

# Wears the shared print design system (DESIGN.md §12). The receipt draws its own
# body rather than going through PdfReportBuilder: it has no report tables, and its
# one number belongs on the stat strip.
class PaymentReceiptPdfService
  THEME = HotelPortal::Reports::Exports::PdfTheme

  VOID_BAND_PADDING = THEME::SPACE[:sm]
  ALLOCATION_NOTE = "This receipt records one payment received. Allocations to folios or invoices do not create additional receipts."
  VOID_NOTE = "This receipt has been voided and is no longer evidence of a payment received."

  def initialize(receipt)
    @receipt = receipt
    @hotel = receipt.hotel
  end

  def generate
    pdf = Prawn::Document.new(page_size: "A4", margin: THEME::PAGE_MARGIN, info: document_info)
    THEME.configure_font(pdf)
    frame = HotelPortal::Reports::Exports::PdfReportFrame.new(
      pdf: pdf,
      hotel: @hotel,
      # The number is the title; the eyebrow says what the number belongs to.
      eyebrow: "Payment receipt",
      report_name: @receipt.public_number,
      metadata: metadata_pairs,
      # Goes to the payer, not into the hotel's filing cabinet.
      confidential: false
    )

    frame.draw_header
    draw_void_notice(pdf) if @receipt.voided?
    HotelPortal::Reports::Exports::PdfStatStrip.new(pdf: pdf).draw([ [ "Amount received", amount_label ] ])
    draw_note(pdf)
    frame.stamp_page_furniture
    pdf.render
  end

  private

  def document_info
    { Title: "Payment Receipt - #{@receipt.public_number}", Author: "WAStays", Creator: "WAStays", CreationDate: Time.current }
  end

  # A voided receipt reads exactly like a valid one at a glance, so the void has to
  # arrive before the amount does.
  def draw_void_notice(pdf)
    label = "VOIDED"
    width = pdf.bounds.width - (VOID_BAND_PADDING * 2)
    label_options = { size: THEME::TYPE[:heading], style: :bold, character_spacing: THEME::LABEL_TRACKING }
    note_options = { size: THEME::TYPE[:body] }
    label_height = pdf.height_of(label, width: width, **label_options)
    note_height = pdf.height_of(VOID_NOTE, width: width, **note_options)
    band_height = label_height + THEME::SPACE[:xs] + note_height + (VOID_BAND_PADDING * 2)

    top = pdf.cursor
    pdf.fill_color THEME::COLORS[:danger_light]
    pdf.fill_rectangle [ 0, top ], pdf.bounds.width, band_height
    pdf.fill_color THEME::COLORS[:danger]
    label_top = top - VOID_BAND_PADDING
    pdf.text_box label, at: [ VOID_BAND_PADDING, label_top ], width: width, height: label_height, **label_options
    pdf.text_box VOID_NOTE, at: [ VOID_BAND_PADDING, label_top - label_height - THEME::SPACE[:xs] ],
      width: width, height: note_height, **note_options

    pdf.move_cursor_to top - band_height
    pdf.move_down THEME::SPACE[:lg]
    pdf.fill_color THEME::COLORS[:ink]
  end

  def draw_note(pdf)
    pdf.fill_color THEME::COLORS[:muted]
    pdf.text ALLOCATION_NOTE, size: THEME::TYPE[:micro]
    pdf.fill_color THEME::COLORS[:ink]
  end

  # Not period-based, so it supplies its own strip. Blank pairs are dropped by the
  # frame, which is why a missing reference costs a column rather than printing a dash.
  def metadata_pairs
    [
      [ "Received", THEME.format_time(@receipt.received_at, @hotel.hotel_time_zone) ],
      [ "Payer", payer_name ],
      [ "Payment method", @receipt.payment_method.to_s.humanize ],
      [ "Reference", @receipt.external_reference ]
    ]
  end

  def amount_label = "#{@receipt.currency} #{THEME.money(@receipt.amount)}"

  def payer_name = @receipt.payer_snapshot.to_h["name"].presence || "Not provided"
end
