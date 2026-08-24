# frozen_string_literal: true

module Receipts
  class Presentation
    PAYMENT_TITLE = "Payment Receipt"
    SECURITY_DEPOSIT_TITLE = "Security Deposit Receipt"
    PAYMENT_NOTE = "This receipt records one payment received. Allocations to folios or invoices do not create additional receipts."
    SECURITY_DEPOSIT_NOTE = "This amount is a refundable security deposit. It is not room revenue. The hotel will release or apply the deposit during settlement."

    attr_reader :receipt

    def initialize(receipt)
      @receipt = receipt
    end

    def security_deposit?
      receipt.deposit&.kind_security? || false
    end

    def title
      security_deposit? ? SECURITY_DEPOSIT_TITLE : PAYMENT_TITLE
    end

    def amount_label
      security_deposit? ? "Amount held" : "Amount received"
    end

    def note
      security_deposit? ? SECURITY_DEPOSIT_NOTE : PAYMENT_NOTE
    end

    def void_note
      if security_deposit?
        "This receipt has been voided and is no longer evidence of a security deposit received."
      else
        "This receipt has been voided and is no longer evidence of a payment received."
      end
    end

    def filename
      "#{security_deposit? ? 'security-deposit' : 'payment'}-receipt-#{receipt.public_number}.pdf"
    end

    def email_subject
      "#{title.capitalize} #{receipt.public_number}"
    end

    def workspace_type
      return "Group security deposit receipt" if security_deposit? && receipt.deposit.group_booking_id?
      return "Security deposit receipt" if security_deposit?
      return "Group deposit receipt" if receipt.deposit&.group_booking_id?
      return "Deposit receipt" if receipt.deposit.present?

      "Payment receipt"
    end
  end
end
