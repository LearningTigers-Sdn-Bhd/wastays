# frozen_string_literal: true

class FinancialAuditEvent < ApplicationRecord
  EVENT_TYPES = %w[
    folio_transaction_created
    folio_transaction_reversed
    folio_closed_for_checkout
    folio_reopened_for_correction
    closed_date_override_posted
    audit_blocker_resolution_posted
    night_audit_started
    night_audit_blocked
    night_audit_completed
    night_audit_force_rolled
    night_audit_failed
    business_date_audit_started
    business_date_audit_blocked
    business_date_closed
    business_date_force_closed
    business_date_opened
    folio_forecasts_refreshed
  ].freeze

  belongs_to :hotel
  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :folio_transaction, optional: true
  belongs_to :booking_folio, optional: true
  belongs_to :booking, optional: true
  belongs_to :payment_transaction, optional: true
  belongs_to :refund_request, optional: true
  belongs_to :night_audit, optional: true
  belongs_to :hotel_business_date, optional: true

  validates :business_date, :event_type, :source, :occurred_at, presence: true
  validates :event_type, inclusion: { in: EVENT_TYPES }
  validates :metadata, exclusion: { in: [ nil ] }

  before_update :prevent_update
  before_destroy :prevent_destroy

  private

  def prevent_update
    errors.add(:base, "Financial audit events are immutable.")
    throw :abort
  end

  def prevent_destroy
    errors.add(:base, "Financial audit events are immutable and cannot be deleted.")
    throw :abort
  end
end
