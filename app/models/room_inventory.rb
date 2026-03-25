class RoomInventory < ApplicationRecord
  belongs_to :room_type

  validates :date, presence: true
  validates :quantity, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :status, presence: true, inclusion: { in: %w[open closed] }
  validates :date, uniqueness: { scope: :room_type_id }

  scope :open, -> { where(status: 'open') }
  scope :closed, -> { where(status: 'closed') }
end
