# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The sheet that writes the guest details of one amenity. The id in the URL
    # is the amenity, not the detail row, because the row is created on the
    # first save.
    class AmenityDetailsController < HotelPortal::GuestContent::BaseController
      include SheetActionCompletion

      before_action :set_amenity

      def edit
        @detail = @hotel.hotel_amenity_details.find_or_initialize_by(amenity: @amenity)
        render layout: false
      end

      def update
        result = HotelPortal::Amenities::SaveDetail.call(
          hotel: @hotel,
          amenity: @amenity,
          attributes: detail_params
        )
        @detail = result.detail

        if result.success?
          complete_sheet_action(
            destination: hotel_guest_amenities_path(@hotel),
            notice: "#{@amenity.name} details updated successfully.",
            frame: sheet_frame
          )
        else
          render :edit, layout: false, status: :unprocessable_content
        end
      end

      private

      # Only an amenity the property offers can hold guest details, so the
      # lookup is scoped to the selected slugs rather than to every amenity.
      def set_amenity
        @amenity = Amenity.hotel.where(slug: @hotel.amenities).find(params[:id])
      end

      def detail_params
        params.require(:hotel_amenity_detail).permit(
          :location, :opening_hours, :fee_information,
          :reservation_required, :reservation_instructions, :guest_notes
        )
      end

      def sheet_frame
        turbo_frame_request_id.presence || "settings_action_sheet"
      end
    end
  end
end
