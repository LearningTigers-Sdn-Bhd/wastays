class HotelBusinessDate < ApplicationRecord
  class InvalidTransition < StandardError; end

  CURRENT_STATUSES = %w[open audit_running audit_blocked].freeze
  CLOSED_STATUSES = %w[closed force_closed].freeze
  STATUSES = (CURRENT_STATUSES + CLOSED_STATUSES).freeze

  belongs_to :hotel
  belongs_to :force_closed_by, class_name: "User", optional: true
  has_many :financial_audit_events, dependent: :restrict_with_error

  validates :business_date, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :hotel_id, uniqueness: { scope: :business_date }

  before_validation :set_defaults, on: :create
  before_destroy :prevent_destroying_only_current_date

  scope :current, -> { where(status: CURRENT_STATUSES) }
  scope :closed_like, -> { where(status: CLOSED_STATUSES) }
  scope :closed_states, -> { closed_like }
  scope :open, -> { where(status: "open") }
  scope :audit_running, -> { where(status: "audit_running") }
  scope :audit_blocked, -> { where(status: "audit_blocked") }

  def self.for_hotel_date!(hotel:, date:)
    date = date.to_date
    record = find_by(hotel: hotel, business_date: date)
    return record if record
    return initialize_for_hotel!(hotel: hotel, date: date) unless hotel.current_business_date_record

    raise InvalidTransition, "Business date #{date} is not the current accounting business date."
  end

  def self.initialize_for_hotel!(hotel:, date: hotel.business_date_for(Time.current))
    transaction(requires_new: true) do
      hotel.lock!
      hotel.current_business_date_record || create!(hotel: hotel, business_date: date.to_date, opened_at: Time.current)
    end
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    hotel.current_business_date_record || find_by!(hotel: hotel, business_date: date.to_date)
  end

  def self.closed_for?(hotel:, date:)
    hotel_id = hotel.respond_to?(:id) ? hotel.id : hotel
    closed_states.exists?(hotel_id: hotel_id, business_date: date.to_date)
  end

  def closed_or_locked?
    !allows_normal_posting?
  end

  def current?
    CURRENT_STATUSES.include?(status)
  end

  def closed_like?
    CLOSED_STATUSES.include?(status)
  end

  def allows_normal_posting?
    open?
  end

  alias_method :normal_posting_allowed?, :allows_normal_posting?

  def allows_audit_posting?
    audit_running?
  end

  alias_method :audit_posting_allowed?, :allows_audit_posting?

  def allows_blocker_resolution?
    open? || audit_blocked?
  end

  def open_for_staff_operations?
    open?
  end

  STATUSES.each do |status_name|
    define_method("#{status_name}?") do
      status == status_name
    end
  end

  def set_defaults
    self.status ||= "open"
    self.opened_at ||= Time.current
    self.blockers_snapshot ||= {}
  end

  private

  def prevent_destroying_only_current_date
    return unless current?
    return if destroyed_by_association&.active_record == Hotel
    return if hotel.hotel_business_dates.current.where.not(id: id).exists?

    errors.add(:base, "cannot destroy the hotel's only current accounting business date")
    throw(:abort)
  end
end
