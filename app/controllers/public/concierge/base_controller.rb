module Public
  module Concierge
    class BaseController < ApplicationController
      include ConciergeBookingLookup
      include ConciergeBookingSession
      include ConciergeStaySession

      layout "concierge"
      skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

      before_action :set_hotel
      before_action :ensure_concierge_enabled

      private

      # The booking behind whoever is reading, however they proved it.
      #
      # A guest reaches the concierge two ways. They look a booking up with
      # their confirmation code, which leaves a booking cookie for half an
      # hour, or they open their stay link and verify the device, which leaves
      # a stay cookie for the stay. Both are the same guest.
      #
      # Only the first one used to count. A guest who had opened their stay
      # page, tapped through to Recommendations and tried to claim a voucher
      # was sent to a page asking for the confirmation code they had already
      # entered -- and the wallet they came back to was empty, because it was
      # keyed on a booking nothing had resolved.
      def concierge_guest_booking
        current_concierge_booking || current_concierge_stay&.booking
      end
      helper_method :concierge_guest_booking

      # Skip the ApplicationController browser version check — the concierge
      # page must be accessible from all browsers including older mobile Safari.
      # allow_browser registers a lambda that calls the instance method allow_browser,
      # so overriding the instance method here is the correct way to neutralise it.
      def allow_browser(versions:, block:); end

      def set_hotel
        @hotel = Hotel.locate_public!(code: params[:hotel_code], public_id: params[:public_id])
      rescue ActiveRecord::RecordNotFound
        render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
      end

      def ensure_concierge_enabled
        return if @hotel&.concierge_page_available?

        if @hotel&.concierge_available?
          redirect_to hotel_path(@hotel.unique_id, @hotel.public_id), alert: "AI concierge is not available for this hotel."
          return
        end

        render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
      end
    end
  end
end
