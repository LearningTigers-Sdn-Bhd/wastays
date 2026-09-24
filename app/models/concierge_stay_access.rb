# frozen_string_literal: true

# One stable link for one stay. The guest opens it on any device. Each device
# then verifies one time and gets its own stay session.
class ConciergeStayAccess < ApplicationRecord
  include HotelScopable

  MAX_ATTEMPTS = 5
  ATTEMPT_WINDOW = 1.hour
  LOCK_DURATION = 1.hour
  ID_LENGTH = 12
  MAX_SENDS = 3
  SEND_WINDOW = 1.hour

  belongs_to :booking

  validates :stay_access_id, presence: true, uniqueness: true
  validates :booking_id, uniqueness: { conditions: -> { where(revoked_at: nil) } }, unless: :revoked?
  validates :attempt_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :send_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :assign_stay_access_id, on: :create

  scope :live, -> { where(revoked_at: nil) }

  def revoked?
    revoked_at.present?
  end

  def locked?(now: Time.current)
    locked_until.present? && locked_until > now
  end

  def attempt_window_open?(now: Time.current)
    attempt_window_started_at.present? && attempt_window_started_at + ATTEMPT_WINDOW > now
  end

  def send_window_open?(now: Time.current)
    send_window_started_at.present? && send_window_started_at + SEND_WINDOW > now
  end

  def sends_left(now: Time.current)
    return MAX_SENDS unless send_window_open?(now: now)

    [ MAX_SENDS - send_count, 0 ].max
  end

  def attempts_left(now: Time.current)
    return MAX_ATTEMPTS unless attempt_window_open?(now: now)

    [ MAX_ATTEMPTS - attempt_count, 0 ].max
  end

  private

  def assign_stay_access_id
    self.stay_access_id ||= SecureRandom.alphanumeric(ID_LENGTH)
  end
end
