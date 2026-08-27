# frozen_string_literal: true

class RoomGroup < ApplicationRecord
  include HotelScopable

  has_many :room_types, dependent: :nullify
  has_many :rooms, dependent: :nullify
  has_many :active_rooms, -> { active }, class_name: "Room", inverse_of: :room_group

  validates :name, presence: true, uniqueness: { scope: :hotel_id }
end
