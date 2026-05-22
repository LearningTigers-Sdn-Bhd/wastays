class HotelBusinessDate < ApplicationRecord
  class InvalidTransition < StandardError; end

  STATUSES = %w[open audit_running audit_blocked closed reopened force_closed].freeze

  belongs_to :hotel
  has_many :financial_audit_events, dependent: :restrict_with_error

  validates :business_date, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :hotel_id, uniqueness: { scope: :business_date }

  before_validation :set_defaults, on: :create

  scope :closed_states, -> { where(status: %w[closed force_closed]) }

  def self.for_hotel_date!(hotel:, date:)
    date = date.to_date
    find_by(hotel: hotel, business_date: date) || transaction(requires_new: true) do
      create!(hotel: hotel, business_date: date, opened_at: Time.current)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    find_by!(hotel: hotel, business_date: date)
  end

  def self.closed_for?(hotel:, date:)
    hotel_id = hotel.respond_to?(:id) ? hotel.id : hotel
    closed_states.exists?(hotel_id: hotel_id, business_date: date.to_date)
  end

  def start_audit!
    transition!(to: "audit_running", from: %w[open audit_blocked reopened]) do
      self.audit_started_at = Time.current
      self.blockers_snapshot = {}
      self.blocked_at = nil
    end
  end

  def block_audit!(blockers:)
    transition!(to: "audit_blocked", from: %w[audit_running]) do
      self.blocked_at = Time.current
      self.blockers_snapshot = blockers.presence || {}
    end
  end

  def complete_audit!
    transition!(to: "closed", from: %w[audit_running audit_blocked]) do
      self.closed_at = Time.current
      self.blockers_snapshot = {}
      self.blocked_at = nil
    end
  end

  def force_close!
    transition!(to: "force_closed", from: %w[audit_running audit_blocked]) do
      self.closed_at = Time.current
      self.blockers_snapshot ||= {}
      self.blocked_at = nil
      record_force_close_audit_event!
    end
  end

  def open_next_business_date!
    next_date = business_date + 1.day
    next_business_date = self.class.find_by(hotel: hotel, business_date: next_date) || create_next_business_date!(next_date)

    next_business_date.with_lock do
      unless next_business_date.open?
        raise InvalidTransition, "Next business date #{next_business_date.business_date} is already #{next_business_date.status}"
      end

      next_business_date.opened_at ||= Time.current
      next_business_date.blockers_snapshot ||= {}
      next_business_date.save! if next_business_date.changed?
    end

    next_business_date
  end

  def retry_audit!
    start_audit!
  end

  def closed_or_locked?
    %w[audit_running audit_blocked closed force_closed].include?(status)
  end

  def normal_posting_allowed?
    status == "open"
  end

  def audit_posting_allowed?
    status == "audit_running"
  end

  STATUSES.each do |status_name|
    define_method("#{status_name}?") do
      status == status_name
    end
  end

  private

  def record_force_close_audit_event!
    FinancialControls::AuditEventRecorder.call!(
      hotel: hotel,
      business_date: business_date,
      event_type: "business_date_force_closed",
      source: "system",
      metadata: {
        reason: "Manual force roll initiated",
        blockers_at_time_of_roll: blockers_snapshot
      }
    )
  end

  def create_next_business_date!(next_date)
    self.class.transaction(requires_new: true) do
      self.class.create!(hotel: hotel, business_date: next_date, status: "open", opened_at: Time.current, blockers_snapshot: {})
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    self.class.find_by!(hotel: hotel, business_date: next_date)
  end

  def set_defaults
    self.status ||= "open"
    self.opened_at ||= Time.current
    self.blockers_snapshot ||= {}
  end

  def transition!(to:, from:)
    raise InvalidTransition, "Cannot transition business date from #{status} to #{to}" unless from.include?(status)

    self.status = to
    yield if block_given?
    save!
  end
end
