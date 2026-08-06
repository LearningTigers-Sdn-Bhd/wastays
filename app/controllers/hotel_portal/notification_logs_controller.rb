# frozen_string_literal: true

class HotelPortal::NotificationLogsController < HotelPortal::ReportsBaseController
  before_action :authorize_view_notification_logs!
  before_action :authorize_manage_bookings!, only: [ :resend ]

  def index
    @logs = filtered_logs
    @notification_summary = notification_summary(@logs)

    respond_to do |format|
      format.html { @logs = @logs.page(params[:page]).per(20) }
      format.csv do
        send_data HotelPortal::Reports::NotificationLogCsvExportService.new(logs: @logs).generate,
          filename: export_filename("csv"), type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data HotelPortal::Reports::NotificationLogExcelExportService.new(
          hotel: current_hotel, logs: @logs, period_label: "All records"
        ).generate,
          filename: export_filename("xlsx"),
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      end
      format.pdf do
        send_data HotelPortal::Reports::NotificationLogPdfExportService.new(
          hotel: current_hotel, logs: @logs, period_label: "All records"
        ).generate,
          filename: export_filename("pdf"), type: "application/pdf"
      end
    end
  end

  def resend
    original = current_hotel.notification_deliveries.find(params[:id])
    resend_reason = params[:resend_reason].to_s.strip

    if resend_reason.blank?
      redirect_to hotel_notification_logs_path(current_hotel), alert: "Resend reason is required."
      return
    end

    unless original.status.in?(%w[sent failed skipped])
      redirect_to hotel_notification_logs_path(current_hotel), alert: "Only sent, failed, or skipped notifications can be resent."
      return
    end

    payload = original.payload.to_h.merge(
      "resend_reason" => resend_reason,
      "resend_requested_by" => current_user.email,
      "resent_from_delivery_id" => original.id
    )

    delivery = NotificationDelivery.create!(
      hotel: current_hotel,
      booking: original.booking,
      notification_type: original.notification_type,
      channel: original.channel,
      trigger_event: "manual_resend",
      status: "pending",
      payload: payload,
      idempotency_key: [
        original.hotel_id,
        original.booking_id,
        original.notification_type,
        original.channel,
        "manual_resend",
        Time.current.to_i,
        SecureRandom.hex(4)
      ].join(":")
    )

    Notifications::DeliverJob.perform_later(delivery.id)
    redirect_to hotel_notification_logs_path(current_hotel), notice: "Notification queued for resend."
  end

  private

  def filtered_logs
    logs = current_hotel.notification_deliveries.includes(:booking).order(created_at: :desc)

    if params[:query].present?
      query = "%#{ActiveRecord::Base.sanitize_sql_like(params[:query].to_s.strip.downcase)}%"
      logs = logs.joins(:booking).where(
        "LOWER(bookings.confirmation_token) LIKE :q OR LOWER(bookings.guest_name) LIKE :q OR LOWER(bookings.guest_email) LIKE :q OR LOWER(bookings.guest_phone) LIKE :q OR LOWER(COALESCE(notification_deliveries.error_message, '')) LIKE :q",
        q: query
      )
    end

    logs = logs.where(notification_type: params[:notification_type]) if params[:notification_type].present?
    logs = logs.where(channel: params[:channel]) if params[:channel].present?
    logs = logs.where(status: params[:status]) if params[:status].present?
    logs
  end

  def notification_summary(logs)
    counts = logs.reorder(nil).group(:status).count

    {
      total: counts.values.sum,
      failed: counts.fetch("failed", 0),
      pending: counts.fetch("pending", 0),
      sent: counts.fetch("sent", 0)
    }
  end

  def export_filename(extension) = "notification-logs-#{Date.current}.#{extension}"

  def authorize_view_notification_logs!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("view_audit_logs", hotel: current_hotel)
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
