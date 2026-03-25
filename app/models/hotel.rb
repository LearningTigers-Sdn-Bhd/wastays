class Hotel < ApplicationRecord
  include AccountScopable

  has_many :user_hotel_accesses, dependent: :destroy
  has_many :users, through: :user_hotel_accesses
  has_one :property_policy, dependent: :destroy

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
end
