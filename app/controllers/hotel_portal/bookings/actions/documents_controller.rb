# frozen_string_literal: true

module HotelPortal
  module Bookings
    module Actions
      class DocumentsController < OverviewBaseController
        before_action :authorize_manage_bookings!, only: :resend

        def show
          @workspace_presenter = workspace_presenter
          @quick_documents = @workspace_presenter.quick_documents unless @booking.group_booking_id?
          @invoice_delivery_preview = Notifications::InvoiceDelivery.preview(
            hotel: current_hotel,
            bookings: @workspace_presenter.document_context_bookings
          )
        end

        def resend
          result = Notifications::InvoiceDelivery.queue(
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

        def context_bookings
          workspace_presenter.document_context_bookings
        end

        def workspace_presenter
          @workspace_presenter ||= HotelPortal::Bookings::WorkspacePresenter.new(
            @booking,
            params: { tab: "documents" },
            hotel: current_hotel,
            user: current_user
          )
        end
      end
    end
  end
end
