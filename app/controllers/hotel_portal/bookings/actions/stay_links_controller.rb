# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class StayLinksController < BaseController
        def create
          result = ::Concierge::StayAccess::SendLink.new(
            booking: @booking,
            reason: :manual_resend
          ).call

          if result.success?
            redirect_to @return_to,
              notice: "Stay link sent to #{result.masked_email}.",
              status: :see_other
          else
            redirect_to @return_to, alert: result.error, status: :see_other
          end
        end
      end
    end
  end
end
