class PreCheckin < ApplicationRecord
  belongs_to :booking
  has_one_attached :signature

  validates :status, presence: true
  validates :token, presence: true, uniqueness: true
  validates :booking_id, uniqueness: true

  STATUSES = %w[pending in_progress completed failed].freeze
  DOCUMENT_STATUSES = %w[pending uploaded verified rejected].freeze
  SIGNATURE_STATUSES = %w[pending signed].freeze

  before_validation :generate_token, on: :create

  def completed?
    status == "completed"
  end

  private

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end
end
