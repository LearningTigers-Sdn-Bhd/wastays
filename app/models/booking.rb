class Booking < ApplicationRecord
  belongs_to :booking_quote, optional: true
  belongs_to :hotel
  has_many :booking_rooms, dependent: :destroy
  has_many :booking_notes, dependent: :destroy
  has_many :booking_guests, dependent: :destroy
  has_many :guests, through: :booking_guests
  has_one :pre_checkin, dependent: :destroy

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
