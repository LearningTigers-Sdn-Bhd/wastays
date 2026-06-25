# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Transactions
      class RepairNoShowFoliosController < BaseController
        before_action :authorize_folio_corrections!
        before_action :set_booking

        def show
          return redirect_to hotel_booking_path(current_hotel, @booking), alert: "Only no-show bookings can have tourism tax repaired." unless @booking.status == "no_show"

          @tourism_tax_charges = ::Bookings::RepairNoShowTourismTax.eligible_charges_for(@booking)
          return redirect_to hotel_booking_path(current_hotel, @booking), alert: "This booking has no no-show tourism tax to repair." if @tourism_tax_charges.empty?

          @tourism_tax_total = @tourism_tax_charges.sum(&:amount)
          @projected_balances = @tourism_tax_charges.group_by(&:booking_folio).to_h do |folio, charges|
            [ folio, folio.outstanding_balance.to_d - charges.sum(&:amount) ]
          end
          render "hotel_portal/bookings/transactions/repair_no_show_folio/offcanvas"
        end

        private

        def authorize_folio_corrections!
          raise Pundit::NotAuthorizedError unless current_user.has_permission?("post_folio_corrections", hotel: current_hotel)
        end
      end
    end
  end
end
