# frozen_string_literal: true

module HotelPortal
  class StaffNotificationsController < BaseController
    def update
      notification = current_user.staff_notifications.where(hotel: current_hotel).find(params[:id])
      notification.update!(read_at: Time.current)

      redirect_to notification_destination(notification), status: :see_other
    end

    private

    def notification_destination(notification)
      path = notification.action_path.to_s
      hotel_prefix = "/hotel/#{current_hotel.to_param}/"
      path.start_with?(hotel_prefix) ? path : hotel_dashboard_path(current_hotel)
    end
  end
end
