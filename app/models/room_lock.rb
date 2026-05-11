# frozen_string_literal: true

class RoomLock < ApplicationRecord
  belongs_to :hotel
  belongs_to :user
  belongs_to :room_type

  validates :room_number, presence: true
  validates :expires_at, presence: true
  validates :room_number, uniqueness: { scope: [ :hotel_id, :room_type_id ], message: "is currently being assigned by another staff member" }

  before_create :log_creation

  scope :active, -> { where("expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }

  def self.cleanup_expired!
    expired.delete_all
  end

  def expired?
    expires_at <= Time.current
  end

  def refresh!(duration = 10.minutes)
    update!(expires_at: Time.current + duration)
  end

  private

  def log_creation
    Rails.logger.info "[ROOM LOCK] Creating lock for room #{room_number} in hotel #{hotel_id} for user #{user_id}"
  end
end
