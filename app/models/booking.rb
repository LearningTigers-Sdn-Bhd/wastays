class Booking < ApplicationRecord
  belongs_to :booking_quote, optional: true
  belongs_to :hotel
  has_many :booking_rooms, dependent: :destroy
  has_many :booking_notes, dependent: :destroy
  has_many :booking_guests, dependent: :destroy
  has_many :guests, through: :booking_guests
  has_one :pre_checkin, dependent: :destroy
  attr_accessor :estimated_arrival_time
  attr_accessor :guest_government_id

  PRE_CHECKIN_STATUSES = %w[not_started pending in_progress completed failed].freeze
  GUARANTEE_METHODS = %w[none pre_checkin_completed manual_at_hotel card_authorization_document charge_now].freeze
  DEPOSIT_STATUSES = %w[not_required pending_at_hotel authorized collected released failed].freeze

  validates :pre_checkin_status, inclusion: { in: PRE_CHECKIN_STATUSES, allow_nil: true }
  validates :guarantee_method, inclusion: { in: GUARANTEE_METHODS, allow_nil: true }
  validates :deposit_status, inclusion: { in: DEPOSIT_STATUSES, allow_nil: true }

  def primary_guest
    booking_guests.find_by(is_primary: true)&.guest
  end

  validates :guest_name, :guest_email, :guest_phone, presence: true
  validates :check_in, :check_out, :adults, :total_amount, :confirmation_token, presence: true
  validates :confirmation_token, uniqueness: true

  before_validation :generate_confirmation_token, on: :create

  STATUSES = %w[pending confirmed checked_in cancelled completed].freeze
  PAYMENT_STATUSES = %w[pending authorized captured failed refunded].freeze

  scope :confirmed, -> { where(status: "confirmed") }
  scope :checked_in, -> { where(status: "checked_in") }
  scope :completed, -> { where(status: "completed") }
  scope :active, -> { where(status: [ "confirmed", "checked_in" ]) }
  scope :revenue_generating, -> { where(status: [ "confirmed", "checked_in", "completed" ]) }

  def checked_in?
    status == "checked_in"
  end

  def checked_out?
    status == "completed"
  end

  def pre_checkin_display_status
    metadata = pre_checkin&.metadata || {}
    has_real_pre_checkin_data = pre_checkin.present? && (
      pre_checkin.completed_at.present? ||
      metadata["submitted_at"].present? ||
      metadata["guest_government_id"].present? ||
      metadata["estimated_arrival_time"].present?
    )

    return "not_started" if status == "completed" && !has_real_pre_checkin_data
    return "completed" if has_real_pre_checkin_data && (pre_checkin_status == "completed" || pre_checkin&.completed?)
    return "failed" if has_real_pre_checkin_data && (pre_checkin_status == "failed" || pre_checkin&.status == "failed")
    return "pending" if status == "confirmed"
    return "not_started" unless has_real_pre_checkin_data

    pre_checkin_status.presence || pre_checkin&.status.presence || "not_started"
  end

  def tourism_tax?
    tourism_tax_applied && tourism_tax_amount.positive?
  end

  def tourism_tax?
    tourism_tax_applied && tourism_tax_amount.positive?
  end

  private

  def generate_confirmation_token
    self.confirmation_token ||= "WS-#{SecureRandom.alphanumeric(8).upcase}"
  end
end
