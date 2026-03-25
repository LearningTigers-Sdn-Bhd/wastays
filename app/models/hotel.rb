class Hotel < ApplicationRecord
  include AccountScopable

  has_many :user_hotel_accesses, dependent: :destroy
  has_many :users, through: :user_hotel_accesses
  has_one :property_policy, dependent: :destroy
  has_many :room_types, dependent: :destroy
  has_many :inventory_audit_logs, dependent: :destroy

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
