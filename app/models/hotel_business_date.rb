class HotelBusinessDate < ApplicationRecord
  class InvalidTransition < StandardError; end

  STATUSES = %w[open audit_running audit_blocked closed reopened force_closed].freeze

  belongs_to :hotel

  validates :business_date, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :hotel_id, uniqueness: { scope: :business_date }

  before_validation :set_defaults, on: :create

  scope :closed_states, -> { where(status: %w[closed force_closed]) }

  def self.for_hotel_date!(hotel:, date:)
    find_or_create_by!(hotel: hotel, business_date: date.to_date) do |business_date|
      business_date.opened_at = Time.current
    end
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
    transition!(to: "closed", from: %w[audit_running]) do
      self.closed_at = Time.current
      self.blockers_snapshot = {}
      self.blocked_at = nil
    end
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
