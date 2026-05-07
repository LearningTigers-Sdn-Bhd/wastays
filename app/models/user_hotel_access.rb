class UserHotelAccess < ApplicationRecord
  belongs_to :user
  belongs_to :hotel
  belongs_to :role

  validates :user_id, uniqueness: { scope: :hotel_id }

  scope :active, -> { where(deactivated_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }

  def active?
    deactivated_at.nil?
  end

  def deactivate!
    update!(deactivated_at: Time.current)
  end

  def reactivate!
    update!(deactivated_at: nil)
  end
end
