class InventoryAuditLog < ApplicationRecord
  belongs_to :hotel
  belongs_to :room_type, optional: true
  belongs_to :user

  validates :action_type, presence: true
end
