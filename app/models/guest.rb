class Guest < ApplicationRecord
  has_many :booking_guests, dependent: :destroy
  has_many :bookings, through: :booking_guests

  encrypts :email
  encrypts :phone
  encrypts :government_id

  validates :name, presence: true
  validates :country, presence: true
  validates :gender, inclusion: { in: %w[male female other], message: "must be male, female, or other" }, allow_blank: true
  validates :document_type, inclusion: { in: %w[ic passport], message: "must be IC or passport" }
  validates :government_id, presence: true

  GENDERS = %w[male female other].freeze
  DOCUMENT_TYPES = %w[ic passport].freeze

  # We allow phone/email to be present or missing for soft matches, 
  # but they must be unique if present? Actually multiple guests might share email/phone (family).
  # The spec says matching is conservative.

  before_validation :normalize_identity_fields

  def normalized_country
    country&.split&.map(&:capitalize)&.join(' ')
  end

  private

  def normalize_identity_fields
    self.gender = gender&.downcase
    self.document_type = document_type&.downcase
    self.country = normalized_country
  end
end
