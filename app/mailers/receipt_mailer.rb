# frozen_string_literal: true

class ReceiptMailer < ApplicationMailer
  def payment_receipt(receipt)
    @receipt = receipt
    @hotel = receipt.hotel
    @presentation = Receipts::Presentation.new(receipt)
    attachments[@presentation.filename] = {
      mime_type: "application/pdf",
      content: PaymentReceiptPdfService.new(receipt).generate
    }

    mail(
      to: receipt.payer_snapshot.to_h.fetch("email"),
      subject: @presentation.email_subject
    )
  end
end
