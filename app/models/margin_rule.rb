class MarginRule < ApplicationRecord
  belongs_to :settable, polymorphic: true, optional: true

  before_validation :normalize_target_fields

  validates :rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :status, presence: true

  STATUSES = %w[active inactive].freeze

  scope :active, -> { where(status: "active") }

  private

  def normalize_target_fields
    self.settable_type = nil if settable_type.blank?
    self.settable_id = nil if settable_id.blank?
  end
end
