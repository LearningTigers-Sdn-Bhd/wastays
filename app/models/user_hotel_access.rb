class UserHotelAccess < ApplicationRecord
  belongs_to :user
  belongs_to :hotel
  belongs_to :role

  validates :user_id, uniqueness: { scope: :hotel_id }
end
