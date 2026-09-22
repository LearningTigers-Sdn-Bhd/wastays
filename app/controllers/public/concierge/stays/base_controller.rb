module Public
  module Concierge
    module Stays
      # The gate for every stay page. It runs before any shared service, so a
      # service always receives its booking from a verified session and never
      # from a request parameter.
      class BaseController < Public::Concierge::BaseController
        include ConciergeStaySession

        before_action :set_stay_access
        before_action :require_stay_session

        private

        def set_stay_access
          @stay_access = ConciergeStayAccess.for_hotel(@hotel)
            .live
            .find_by(stay_access_id: params[:stay_access_id])

          return render_stay_unavailable if @stay_access.blank?
          return render_stay_unavailable unless stay_eligible?

          @stay_expires_at = eligibility.expires_at
        end

        # A session for another stay at the same hotel lands here too. The guest
        # gets the locked page rather than a refusal, so a guest with two
        # bookings can verify the second one instead of being stuck.
        def require_stay_session
          return if current_concierge_stay&.id == @stay_access.id

          render_stay_locked
        end

        def eligibility
          @eligibility ||= ::Concierge::StayAccess::Eligibility.new(booking: @stay_access.booking).call
        end

        def stay_eligible?
          eligibility.success?
        end

        def stay_booking
          current_concierge_stay.booking
        end

        # The locked page shows the hotel and nothing about the stay. The hotel
        # is already public through the QR code. The guest name, the room, the
        # dates, the status, and the money are not.
        def render_stay_locked(status: :ok)
          render "public/concierge/stays/overview/locked", status: status
        end

        def render_stay_unavailable
          clear_concierge_stay_session
          render "public/concierge/stays/overview/unavailable", status: :not_found
        end

        def stay_path
          concierge_stay_path(@hotel.unique_id, @hotel.public_id, params[:stay_access_id])
        end
      end
    end
  end
end
