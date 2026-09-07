# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class AmenitiesController < HotelPortal::GuestContent::BaseController
      def show
        prepare_page
      end

      def update
        service = HotelPortal::UpdateAmenityDetails.new(hotel: @hotel, rows: amenity_rows)
        if service.call
          redirect_to hotel_guest_amenities_path(@hotel), notice: "Amenity details updated successfully."
        else
          prepare_page
          flash.now[:alert] = "Amenity details could not be updated."
          render :show, status: :unprocessable_content
        end
      end

      private

      def prepare_page
        @amenities = Amenity.hotel.where(slug: @hotel.amenities).ordered
        @details = @hotel.hotel_amenity_details.where(amenity: @amenities).index_by(&:amenity_id)
      end

      def amenity_rows
        params.fetch(:amenity_details, {}).permit!.to_h
      end
    end
  end
end
