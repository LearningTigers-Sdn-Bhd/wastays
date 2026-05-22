module Public
  module Concierge
    class BaseController < ApplicationController
      include ConciergeBookingLookup
      include ConciergeBookingSession

      layout "concierge"
      skip_before_action :authenticate_user! if respond_to?(:authenticate_user!)

      before_action :set_hotel
      before_action :ensure_concierge_enabled

      private

      # Skip the ApplicationController browser version check — the concierge
      # page must be accessible from all browsers including older mobile Safari.
      # allow_browser registers a lambda that calls the instance method allow_browser,
      # so overriding the instance method here is the correct way to neutralise it.
      def allow_browser(versions:, block:); end

      def mobile_request?
        request.user_agent.to_s =~ /Mobile|Android|iPhone/i
      end

      def set_hotel
        @hotel = Hotel.friendly.find(params[:hotel_slug])
      rescue ActiveRecord::RecordNotFound
        render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
      end

      def ensure_concierge_enabled
        return if @hotel&.concierge_available?
        render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
      end
    end
  end
end
