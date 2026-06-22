# frozen_string_literal: true

class EInvoiceSubmission < ApplicationRecord
  belongs_to :hotel
  belongs_to :booking
  belongs_to :payout_batch, optional: true

  STATUSES = %w[pending submitted valid invalid cancelled].freeze
  SUBMISSION_MODES = %w[taxpayer intermediary].freeze
  FUND_COLLECTORS = Booking::FUND_COLLECTORS
  DOCUMENT_SCENARIOS = {
    "guest_invoice" => "Guest e-invoice by WAStays",
    "hotel_intermediary_guest_invoice" => "Guest e-invoice by hotel",
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
  validates :booking_id, uniqueness: {
    scope: :document_scenario,
    conditions: -> { where.not(status: "cancelled") },
    message: "already has an active submission for this document scenario"
  }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :valid, -> { where(status: "valid") }
  scope :pending_or_submitted, -> { where(status: %w[pending submitted]) }
  scope :for_scenario, ->(scenario) { where(document_scenario: scenario) }
  scope :guest_invoice, -> { for_scenario("guest_invoice") }
  scope :guest_facing, -> { where(document_scenario: %w[guest_invoice hotel_intermediary_guest_invoice]) }
  scope :payout_self_billed, -> { for_scenario("payout_self_billed_invoice") }

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

  def intermediary_submission?
    submission_mode == "intermediary"
  end
end
