class Hotel < ApplicationRecord
  include AccountScopable

  has_many :user_hotel_accesses, dependent: :destroy
  has_many :users, through: :user_hotel_accesses
  has_one :property_policy, dependent: :destroy
  has_many :room_types, dependent: :destroy
  has_many :inventory_audit_logs, dependent: :destroy
  has_many :payment_settings, as: :settable, dependent: :destroy
  has_many :bookings, dependent: :destroy
  has_many :booking_quotes, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true
  validates :city, presence: true
  validates :country, presence: true

  STATUSES = %w[
    registered
    email_verified
    profile_incomplete
    rooms_incomplete
    inventory_incomplete
    pending_review
    approved
    live
    suspended
  ].freeze

  def active?
    %w[approved live].include?(status)
  end

  def effective_payment_setting(gateway)
    # 1. Check hotel-level override
    setting = payment_settings.active.find_by(gateway: gateway)
    return setting if setting

    # 2. Check account-level setting
    account.payment_settings.active.find_by(gateway: gateway)
  end

  def effective_margin_rate(room_type = nil)
    # 1. Check room-type override
    if room_type
      rule = MarginRule.active.find_by(settable: room_type)
      return rule.rate if rule
    end

    # 2. Check hotel-level override
    rule = MarginRule.active.find_by(settable: self)
    return rule.rate if rule

    # 3. Check global default (where settable is nil)
    rule = MarginRule.active.find_by(settable: nil)
    rule&.rate || 10.0 # Default to 10% if nothing set
  end

  def onboarding?
    %w[registered email_verified profile_incomplete rooms_incomplete inventory_incomplete].include?(status)
  end

  def profile_completed?
    !status.in?(['registered', 'email_verified'])
  end

  def policies_completed?
    !status.in?(['registered', 'email_verified', 'profile_incomplete'])
  end

  def rooms_completed?
    !status.in?(['registered', 'email_verified', 'profile_incomplete', 'rooms_incomplete'])
  end

  def ready_for_review?
    status == 'inventory_incomplete'
  end

  def complete_profile!
    update(status: 'profile_incomplete') if status == 'registered'
  end

  def complete_policies!
    update(status: 'rooms_incomplete') if status == 'profile_incomplete'
  end

  def complete_rooms!
    update(status: 'inventory_incomplete') if status == 'rooms_incomplete'
  end

  def submit_for_review!
    update(status: 'pending_review') if ready_for_review?
  end
end
