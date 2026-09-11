# frozen_string_literal: true

class HotelGuestInstruction < ApplicationRecord
  belongs_to :hotel

  validates :hotel_id, uniqueness: true
end
