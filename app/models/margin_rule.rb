class MarginRule < ApplicationRecord
  belongs_to :settable, polymorphic: true, optional: true

  validates :rate, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
  validates :status, presence: true

  STATUSES = %w[active inactive].freeze

  scope :active, -> { where(status: 'active') }
end
