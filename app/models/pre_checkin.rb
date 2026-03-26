class PreCheckin < ApplicationRecord
  belongs_to :booking

  validates :status, presence: true
  validates :token, presence: true, uniqueness: true

  STATUSES = %w[pending in_progress completed failed].freeze
  DOCUMENT_STATUSES = %w[pending uploaded verified rejected].freeze
  SIGNATURE_STATUSES = %w[pending signed].freeze

  before_validation :generate_token, on: :create

  private

  def generate_token
    self.token ||= SecureRandom.hex(20)
  end
end
