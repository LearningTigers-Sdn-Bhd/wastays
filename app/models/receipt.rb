# frozen_string_literal: true

class Receipt < ApplicationRecord
  belongs_to :hotel
  belongs_to :folio_transaction, optional: true
  belongs_to :deposit, optional: true
  belongs_to :ar_payment, optional: true
  belongs_to :payment_transaction, optional: true

  has_secure_token :access_token

  enum :status, { issued: "issued", voided: "voided" }, validate: true

  validates :receipt_number, :receipt_year, :public_number, :amount, :currency, :payment_method, :received_at, :issued_at, presence: true
  validates :receipt_number, uniqueness: { scope: [ :hotel_id, :receipt_year ] }
  validates :public_number, :access_token, uniqueness: true
  validates :amount, numericality: { greater_than: 0 }
  validate :exactly_one_source
  validate :payment_transaction_matches_hotel

  after_create_commit :enqueue_email

  private

  def enqueue_email
    SendPaymentReceiptEmailJob.perform_later(id) if payer_snapshot.to_h["email"].present?
  end

  def exactly_one_source
    return if [ folio_transaction, deposit, ar_payment ].count(&:present?) == 1

    errors.add(:base, "Receipt must belong to exactly one payment source")
  end

  def payment_transaction_matches_hotel
    return if payment_transaction.blank? || hotel.blank?

    source_hotel_id = payment_transaction.booking&.hotel_id ||
      payment_transaction.ar_payment&.hotel_id ||
      payment_transaction.corporate_ar_payment_intent&.hotel_id ||
      payment_transaction.booking_quote&.hotel_id
    errors.add(:payment_transaction, "must belong to the receipt hotel") unless source_hotel_id == hotel_id
  end
end
