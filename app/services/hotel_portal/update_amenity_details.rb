# frozen_string_literal: true

module HotelPortal
  class UpdateAmenityDetails
    def initialize(hotel:, rows:)
      @hotel = hotel
      @rows = rows.to_h
    end

    def call
      amenities = Amenity.hotel.where(slug: hotel.amenities).index_by { |amenity| amenity.id.to_s }

      HotelAmenityDetail.transaction do
        rows.each do |amenity_id, attributes|
          amenity = amenities[amenity_id.to_s]
          next unless amenity

          detail = hotel.hotel_amenity_details.find_or_initialize_by(amenity: amenity)
          detail.update!(permitted_attributes(attributes))
        end
      end

      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    private

    attr_reader :hotel, :rows

    def permitted_attributes(attributes)
      attributes.to_h.slice(
        "location", "opening_hours", "fee_information", "reservation_required",
        "reservation_instructions", "guest_notes"
      )
    end
  end
end
