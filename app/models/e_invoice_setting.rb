# frozen_string_literal: true

class EInvoiceSetting < ApplicationRecord
  belongs_to :hotel

  validates :hotel_tin,
    format: { with: /\A[A-Z]{1,2}\d+\z/, message: "must be a valid TIN (e.g. C1234567890)" },
    allow_blank: true

  # Whether hotel's TIN/BRN are filled in (needed for Phase 2 payout/commission invoices)
  def buyer_configured?
    hotel_tin.present? && hotel_brn.present?
  end
end
