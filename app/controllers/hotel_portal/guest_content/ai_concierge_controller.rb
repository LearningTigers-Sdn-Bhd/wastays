# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # The Configuration sub-tab of AI Concierge. It owns the concierge settings
    # that used to live inside the general Settings controller.
    class AiConciergeController < HotelPortal::GuestContent::BaseController
      def show; end

      def update
        if HotelPortal::SaveAiSettings.call(@hotel, ai_settings_params)
          redirect_to hotel_ai_concierge_settings_path(@hotel), notice: "Settings updated successfully."
        else
          render :show, status: :unprocessable_content
        end
      end

      private

      def ai_settings_params
        params.require(:hotel).permit(
          :guest_chat_enabled, :ai_provider_enabled, :ai_concierge_tone,
          :ai_provider_name, :ai_provider_key
        )
      end
    end
  end
end
