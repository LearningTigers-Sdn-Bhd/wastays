# frozen_string_literal: true

class RoomGroup < ApplicationRecord
  include HotelScopable

  has_many :room_types, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :hotel_id }
end
