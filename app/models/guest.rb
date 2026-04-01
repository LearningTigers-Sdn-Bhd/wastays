class Guest < ApplicationRecord
  has_many :booking_guests, dependent: :destroy
  has_many :bookings, through: :booking_guests

  encrypts :email
  encrypts :phone
  encrypts :government_id

  validates :name, presence: true
  # We allow phone/email to be present or missing for soft matches,
  # but they must be unique if present? Actually multiple guests might share email/phone (family).
  # The spec says matching is conservative.
end
