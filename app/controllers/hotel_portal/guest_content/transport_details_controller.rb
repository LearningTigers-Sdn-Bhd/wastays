# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Getting Around: how a guest reaches the property, how a guest moves after
    # arrival, and where a guest leaves the car.
    #
    # One record behind three sheets. Each sheet patches its own section, so a
    # save writes only the columns that sheet showed.
    class TransportDetailsController < HotelPortal::GuestContent::BaseController
      include SheetActionCompletion

      before_action :load_transport_detail
      before_action :set_section, only: %i[edit update]

      SECTION_TITLES = {
        "directions" => "Directions",
        "transportation" => "Transportation",
        "parking" => "Parking"
      }.freeze

      def show; end

      def edit
        render layout: false
      end

      def update
        if @transport_detail.update(section_params)
          complete_sheet_action(
            destination: hotel_guest_transport_details_path(@hotel),
            notice: "#{SECTION_TITLES.fetch(@section)} saved.",
            frame: sheet_frame
          )
        else
          render :edit, layout: false, status: :unprocessable_content
        end
      end

      private

      def load_transport_detail
        @transport_detail = @hotel.transport_detail || @hotel.build_transport_detail
      end

      # The route constraint already rejects a section this page does not own,
      # so nothing here has to guard the name a second time.
      def set_section
        @section = params[:section]
      end

      def section_params
        params.require(:hotel_transport_detail)
              .permit(*HotelTransportDetail::SECTION_ATTRIBUTES.fetch(@section))
      end

      def sheet_frame
        turbo_frame_request_id.presence || "settings_action_sheet"
      end
    end
  end
end
