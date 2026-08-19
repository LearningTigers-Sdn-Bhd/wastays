# frozen_string_literal: true

class EInvoiceSubmission < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking, optional: true
  belongs_to :payout_batch, optional: true

  STATUSES = %w[pending submitted valid invalid cancelled].freeze
  SUBMISSION_MODES = %w[taxpayer intermediary].freeze
  FUND_COLLECTORS = Booking::FUND_COLLECTORS
  DOCUMENT_SCENARIOS = {
    # The hotel files its own guest e-invoices; WAStays only operates the
    # submission, so the labels name the hotel as issuer.
    "guest_invoice" => "Guest e-invoice",
    "hotel_intermediary_guest_invoice" => "Guest e-invoice filed on the hotel's behalf",
    "ota_commission_self_billed" => "OTA commission (self-billed)",
    "payout_self_billed_invoice" => "Hotel payout record",
    "commission_invoice" => "WAStays service fee invoice",
    "subscription_invoice" => "WAStays subscription invoice"
  }.freeze
  DOCUMENT_TYPES = {
    "01" => "Standard invoice",
    "02" => "Credit Note",
    "03" => "Debit Note",
    "11" => "Self-billed invoice"
  }.freeze

  validates :status, inclusion: { in: STATUSES }
  validates :document_scenario, inclusion: { in: DOCUMENT_SCENARIOS.keys }
  validates :document_type, inclusion: { in: DOCUMENT_TYPES.keys }
  validates :submission_mode, inclusion: { in: SUBMISSION_MODES }
  validates :fund_collector, inclusion: { in: FUND_COLLECTORS }
  # A commission document covers a period and an OTA, not a stay.
  validates :booking_id, presence: true, unless: :ota_commission_self_billed?
  # Only meaningful for booking-scoped documents: ActiveRecord treats two nil
  # booking_ids as duplicates, which would let one commission document per
  # month exist across the whole system. Those are kept unique by their own
  # index on (hotel, OTA, period).
  validates :booking_id, uniqueness: {
    scope: [ :document_scenario, :document_type ],
    conditions: -> { where.not(status: "cancelled") },
    message: "already has an active submission for this document scenario and type"
  }, if: -> { booking_id.present? }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :valid, -> { where(status: "valid") }
  scope :pending_or_submitted, -> { where(status: %w[pending submitted]) }
  scope :for_scenario, ->(scenario) { where(document_scenario: scenario) }
  scope :guest_invoice, -> { for_scenario("guest_invoice") }
  scope :guest_facing, -> { where(document_scenario: %w[guest_invoice hotel_intermediary_guest_invoice]) }
  scope :payout_self_billed, -> { for_scenario("payout_self_billed_invoice") }
  scope :consolidated, -> { where(consolidated: true) }
  scope :guest_requested, -> { where(requested_by_guest: true) }
  scope :unrequested, -> { where(requested_by_guest: false) }
  scope :with_payment_concluded_in_month, ->(month_start, month_end) {
    where(payment_concluded_at: month_start..month_end)
  }

  def document_type_label
    DOCUMENT_TYPES.fetch(document_type, document_type)
  end

  def document_scenario_label
    DOCUMENT_SCENARIOS.fetch(document_scenario, document_scenario)
  end

  def status_label
    {
      "valid" => "Ready",
      "submitted" => "Sent",
      "pending" => "Preparing",
      "invalid" => "Rejected",
      "cancelled" => "Cancelled"
    }.fetch(status, status.humanize)
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

  def stale_pending?
    pending? && uuid.blank? && submission_uid.blank? && created_at < 2.minutes.ago
  end

  def retryable?
    invalid? || stale_pending?
  end

  def cancellable?
    validated? && cancelled_at.nil?
  end

  def refreshable?
    %w[submitted pending].include?(status) && uuid.present?
  end

  def adjustment?
    %w[02 03].include?(document_type)
  end

  def guest_requested?
    requested_by_guest
  end

  def validation_url
    return nil unless uuid.present? && long_id.present?
    base = MyInvois::ClientFactory.sandbox? ? "https://preprod.myinvois.hasil.gov.my" : "https://myinvois.hasil.gov.my"
    "#{base}/#{uuid}/share/#{long_id}"
  end

  def error_message
    return if error_details.blank?

    direct_message = error_details["message"].presence || error_details[:message].presence
    return direct_message if direct_message.present?

    messages = Array(error_details.dig("rejected", "error", "details")).filter_map do |detail|
      detail["message"].presence || detail[:message].presence
    end
    return messages.join(", ") if messages.any?

    nil
  end

  def intermediary_submission?
    submission_mode == "intermediary"
  end

  def ota_commission_self_billed?
    document_scenario == "ota_commission_self_billed"
  end
end
