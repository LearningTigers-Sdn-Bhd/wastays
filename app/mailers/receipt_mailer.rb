# frozen_string_literal: true

class ReceiptMailer < ApplicationMailer
  def payment_receipt(receipt)
    @receipt = receipt
    @hotel = receipt.hotel
    attachments["payment-receipt-#{receipt.public_number}.pdf"] = {
      mime_type: "application/pdf",
      content: PaymentReceiptPdfService.new(receipt).generate
    }

    mail(
      to: receipt.payer_snapshot.to_h.fetch("email"),
      subject: "Payment receipt #{receipt.public_number}"
    )
  end
end
