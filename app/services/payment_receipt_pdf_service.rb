# frozen_string_literal: true

require "prawn"
require "prawn/table"

class PaymentReceiptPdfService
  def initialize(receipt)
    @receipt = receipt
    @hotel = receipt.hotel
  end

  def generate
    Prawn::Document.new(page_size: "A4", margin: 48, info: document_info).tap do |pdf|
      pdf.text @hotel.name.to_s, size: 18, style: :bold
      pdf.text "PAYMENT RECEIPT", size: 20, style: :bold, align: :right
      pdf.move_down 16
      pdf.stroke_horizontal_rule
      pdf.move_down 24
      pdf.table(rows, width: pdf.bounds.width, cell_style: { borders: [ :bottom ], padding: 10 })
      pdf.move_down 28
      pdf.text "#{@receipt.currency} #{format('%.2f', @receipt.amount)}", size: 22, style: :bold, align: :right
      pdf.move_down 40
      pdf.text "This receipt records one payment received. Allocations to folios or invoices do not create additional receipts.", size: 9
    end.render
  end

  private

  def document_info
    { Title: "Payment Receipt - #{@receipt.public_number}", Author: "WAStays", Creator: "WAStays", CreationDate: Time.current }
  end

  def rows
    snapshot = @receipt.payer_snapshot.to_h
    [
      [ "Receipt number", @receipt.public_number ],
      [ "Received", @receipt.received_at.strftime("%d %B %Y %H:%M") ],
      [ "Payer", snapshot["name"].presence || "Not provided" ],
      [ "Payment method", @receipt.payment_method.to_s.humanize ],
      [ "External reference", @receipt.external_reference.presence || "-" ],
      [ "Status", @receipt.status.humanize ]
    ]
  end
end
