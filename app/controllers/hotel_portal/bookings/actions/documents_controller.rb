# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class DocumentsController < OverviewBaseController
        before_action :authorize_manage_bookings!, only: :resend

        def show
          @documents = HotelPortal::Bookings::DocumentsQuery.call(
            booking: @booking,
            group_booking: @booking.group_booking,
            hotel: current_hotel,
            user: current_user
          )
          @invoice_package_preview = package_preview
        end

        def resend
          result = FolioInvoicePackages::QueueDeliveries.call(
            hotel: current_hotel,
            bookings: context_bookings,
            anchor_booking: @booking,
            source: "manual_resend",
            requested_by: current_user
          )

          queued = result.deliveries.count { |delivery| delivery.status == "pending" }
          skipped = result.deliveries.count { |delivery| delivery.status == "skipped" }
          notice = "Queued #{queued} invoice #{'email'.pluralize(queued)}."
          notice += " Skipped #{skipped} #{'payer'.pluralize(skipped)} without a saved email." if skipped.positive?
          complete_action(notice:)
        end

        private

        def package_preview
          FolioInvoicePackages::Preview.call(hotel: current_hotel, bookings: context_bookings)
        end

        def context_bookings
          return [ @booking ] unless @booking.group_booking_id?

          current_hotel.bookings.where(group_booking_id: @booking.group_booking_id).to_a
        end
      end
    end
  end
end
