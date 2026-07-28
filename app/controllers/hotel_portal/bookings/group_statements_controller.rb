# frozen_string_literal: true

module HotelPortal
  module Bookings
    class GroupStatementsController < HotelPortal::BaseController
      before_action :authorize_view_reports!

      def show
        booking = current_hotel.bookings.includes(:group_booking).find(params[:booking_id])
        raise ActiveRecord::RecordNotFound unless booking.group_booking
        hotel_corporate_account = current_hotel.hotel_corporate_accounts.find(params[:hotel_corporate_account_id])

        pdf = ::Reports::AccountsReceivable::GenerateGroupStatement.new(
          hotel: current_hotel,
          group_booking: booking.group_booking,
          hotel_corporate_account:,
          currency: params[:currency],
          printed_by: current_user.name
        ).generate

        send_data pdf,
          filename: "group-statement-#{booking.group_booking.formatted_reservation_number}.pdf",
          type: "application/pdf",
          disposition: "inline"
      rescue ::Reports::AccountsReceivable::GenerateGroupStatement::ValidationError => e
        redirect_to hotel_booking_workspace_path(current_hotel, params[:booking_id], tab: "documents"), alert: e.message
      end

      private

      def authorize_view_reports!
        raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_reports", hotel: current_hotel)
      end
    end
  end
end
