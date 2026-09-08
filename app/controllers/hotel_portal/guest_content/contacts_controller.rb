# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Contact and Escalation: who a guest reaches when the concierge cannot
    # answer, and when that person is there.
    class ContactsController < HotelPortal::GuestContent::BaseController
      def show
        load_page
      end

      def update
        @service = ::GuestContent::SaveContactSetting.new(@hotel, contact_params)
        @guest_contact = @service.contact

        if @service.call
          redirect_to hotel_guest_contact_path(@hotel), notice: "Contact and escalation saved."
        else
          render :show, status: :unprocessable_content
        end
      end

      private

      def load_page
        @guest_contact = @hotel.guest_contact || @hotel.build_guest_contact
      end

      def contact_params
        params.require(:hotel_guest_contact).permit(
          :front_desk_phone, :front_desk_whatsapp, :front_desk_email, :front_desk_extension,
          :front_desk_open_24h, :front_desk_opens_at, :front_desk_closes_at,
          :duty_manager_phone, :after_hours_message,
          :emergency_phone, :emergency_services_number, :emergency_instructions,
          :escalation_attempts, escalation_triggers: []
        )
      end
    end
  end
end
