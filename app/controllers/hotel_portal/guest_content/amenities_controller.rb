# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The Amenities table. Both edits happen in a sheet over this page, so the
    # page itself is read-only.
    class AmenitiesController < HotelPortal::GuestContent::BaseController
      def show
        amenities = Amenity.hotel.where(slug: @hotel.amenities).ordered
        @rows = HotelPortal::GuestContent::AmenityRow.build(hotel: @hotel, amenities: amenities)
      end
    end
  end
end
