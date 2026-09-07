# frozen_string_literal: true

class HotelAmenityDetail < ApplicationRecord
  belongs_to :hotel
  belongs_to :amenity

  validates :amenity_id, uniqueness: { scope: :hotel_id }
  validate :amenity_is_for_hotels

  scope :ordered, -> { joins(:amenity).order("amenities.name") }

  def available?
    hotel.amenities.include?(amenity.slug)
  end

  private

  def amenity_is_for_hotels
    errors.add(:amenity, "must be a hotel amenity") if amenity && !amenity.hotel?
  end
end
