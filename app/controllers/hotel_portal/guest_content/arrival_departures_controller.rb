# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class ArrivalDeparturesController < HotelPortal::GuestContent::BaseController
      def show
        load_page
      end

      def update
        load_page

        if @guest_instruction.update(guest_instruction_params)
          redirect_to hotel_guest_arrival_departure_path(@hotel), notice: "Arrival and departure instructions saved."
        else
          render :show, status: :unprocessable_content
        end
      end

      private

      def load_page
        @guest_instruction = @hotel.guest_instruction || @hotel.build_guest_instruction
        @property_policy = @hotel.property_policy
      end

      def guest_instruction_params
        params.require(:hotel_guest_instruction).permit(:arrival_instructions, :departure_instructions)
      end
    end
  end
end
