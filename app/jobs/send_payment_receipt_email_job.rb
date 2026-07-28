# frozen_string_literal: true

class SendPaymentReceiptEmailJob < ApplicationJob
  queue_as :default

  def perform(receipt_id)
    receipt = Receipt.find_by(id: receipt_id)
    return unless receipt&.payer_snapshot.to_h["email"].present?

    ReceiptMailer.payment_receipt(receipt).deliver_now
  end
end
