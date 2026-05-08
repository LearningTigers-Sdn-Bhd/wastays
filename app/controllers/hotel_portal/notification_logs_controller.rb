# frozen_string_literal: true

class HotelPortal::NotificationLogsController < HotelPortal::BaseController
  before_action :authorize_view_notification_logs!

  def index
    @logs = current_hotel.notification_deliveries.includes(:booking).order(created_at: :desc)

    if params[:query].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)}%"
      @logs = @logs.joins(:booking).where(
        "LOWER(bookings.confirmation_token) LIKE :q OR LOWER(bookings.guest_name) LIKE :q OR LOWER(bookings.guest_email) LIKE :q OR LOWER(bookings.guest_phone) LIKE :q OR LOWER(COALESCE(notification_deliveries.error_message, '')) LIKE :q",
        q: query
      )
    end

    @logs = @logs.where(notification_type: params[:notification_type]) if params[:notification_type].present?
    @logs = @logs.where(channel: params[:channel]) if params[:channel].present?
    @logs = @logs.where(status: params[:status]) if params[:status].present?

    @logs = @logs.page(params[:page]).per(20)
  end

  private

  def authorize_view_notification_logs!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_audit_logs", hotel: current_hotel)
  end
end
