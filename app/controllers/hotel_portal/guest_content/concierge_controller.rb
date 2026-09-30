# frozen_string_literal: true

module HotelPortal
  module GuestContent
    class ConciergeController < HotelPortal::GuestContent::BaseController
      before_action -> { require_feature!("ai_concierge_page") }

      def show; end

      def update
        if HotelPortal::SaveConciergeSettings.call(@hotel, concierge_settings_params)
          redirect_to hotel_concierge_settings_path(@hotel), notice: "Settings updated successfully."
        else
          render :show, status: :unprocessable_content
        end
      end

      private

      def concierge_settings_params
        params.require(:hotel).permit(
          :guest_chat_enabled,
          :concierge_refund_requests_enabled,
          :concierge_menu_style
        )
      end
    end
  end
end
