# frozen_string_literal: true

class EInvoiceSubmission < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking

  STATUSES = %w[pending submitted valid invalid cancelled].freeze
  DOCUMENT_TYPES = {
    "01" => "Invoice",
    "02" => "Credit Note",
    "03" => "Debit Note",
    "11" => "Self-billed Invoice"
  }.freeze

  validates :status, inclusion: { in: STATUSES }
  validates :document_type, inclusion: { in: DOCUMENT_TYPES.keys }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :valid, -> { where(status: "valid") }
  scope :pending_or_submitted, -> { where(status: %w[pending submitted]) }

  def document_type_label
    DOCUMENT_TYPES.fetch(document_type, document_type)
  end

  def status_label
    status.humanize
  end

  def validated?
    status == "valid"
  end

  def cancelled?
    status == "cancelled"
  end

  def invalid?
    status == "invalid"
  end

  def submitted?
    status == "submitted"
  end

  def pending?
    status == "pending"
  end

  def cancellable?
    validated? && cancelled_at.nil?
  end

  def refreshable?
    %w[submitted pending].include?(status) && uuid.present?
  end

  def validation_url
    return nil unless uuid.present? && long_id.present?
    base = MyInvois::ClientFactory.sandbox? ? "https://preprod.myinvois.hasil.gov.my" : "https://myinvois.hasil.gov.my"
    "#{base}/#{uuid}/share/#{long_id}"
  end
end
