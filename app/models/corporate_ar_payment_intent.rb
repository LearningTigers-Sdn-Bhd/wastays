# frozen_string_literal: true

class CorporateArPaymentIntent < ApplicationRecord
  STATUSES = %w[pending checkout_initiated captured failed expired cancelled].freeze

  belongs_to :corporate_account, class_name: "Account"
  belongs_to :user
  belongs_to :hotel
  belongs_to :hotel_corporate_account
  belongs_to :ar_payment, optional: true
  has_many :payment_transactions, dependent: :nullify

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :currency, :gateway, :expires_at, presence: true
  validate :json_payloads_are_not_nil
  validate :references_match_relationship
  validate :relationship_must_be_active, on: :create

  def expired_for_checkout?
    expires_at.present? && expires_at <= Time.current
  end

  private

  def references_match_relationship
    return if hotel_corporate_account.blank?

    errors.add(:hotel, "must match corporate relationship") if hotel.present? && hotel_id != hotel_corporate_account.hotel_id
    if corporate_account.present? && corporate_account_id != hotel_corporate_account.corporate_account_id
      errors.add(:corporate_account, "must match corporate relationship")
    end
  end

  def relationship_must_be_active
    return if hotel_corporate_account&.active?

    errors.add(:hotel_corporate_account, "must be active")
  end

  def json_payloads_are_not_nil
    errors.add(:invoice_snapshots, "can't be nil") if invoice_snapshots.nil?
    errors.add(:remittance_suggestions, "can't be nil") if remittance_suggestions.nil?
    errors.add(:metadata, "can't be nil") if metadata.nil?
  end
end
