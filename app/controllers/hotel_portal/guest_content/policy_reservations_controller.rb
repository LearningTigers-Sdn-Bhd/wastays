# frozen_string_literal: true

module HotelPortal
  module GuestContent
    # Reservation policies, read-only. Room Revenue owns the rows the engine
    # charges from, so this page shows them and links back rather than keeping
    # a second copy.
    class PolicyReservationsController < HotelPortal::GuestContent::BaseController
      def show
        @reservation_policies = HotelPortal::GuestContent::ReservationPolicyPresenter.new(@hotel)
      end
    end
  end
end
