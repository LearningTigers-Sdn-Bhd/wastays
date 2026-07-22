# frozen_string_literal: true

class HotelPortal::AuditLogsController < HotelPortal::BaseController
  before_action -> { require_feature!("full_audit_trail") }

  def index
    @logs = filtered_logs

    respond_to do |format|
      format.html { @logs = @logs.page(params[:page]).per(20) }
      format.csv do
        send_data HotelPortal::Reports::AuditLogCsvExportService.new(logs: @logs).generate,
          filename: export_filename("csv"), type: "text/csv; charset=utf-8"
      end
      format.xlsx do
        send_data HotelPortal::Reports::AuditLogExcelExportService.new(
          hotel: current_hotel, logs: @logs, period_label: period_label
        ).generate,
          filename: export_filename("xlsx"),
          type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      end
      format.pdf do
        send_data HotelPortal::Reports::AuditLogPdfExportService.new(
          hotel: current_hotel, logs: @logs, period_label: period_label
        ).generate,
          filename: export_filename("pdf"), type: "application/pdf"
      end
    end
  end

  private

  def filtered_logs
    logs = current_hotel.inventory_audit_logs.includes(:room_type, :user).order(created_at: :desc)
    logs = logs.where(room_type_id: params[:room_type_id]) if params[:room_type_id].present?
    logs = logs.where(action_type: params[:action_type]) if params[:action_type].present?
    if params[:start_date].present? && params[:end_date].present?
      logs = logs.where(created_at: params[:start_date].to_date.beginning_of_day..params[:end_date].to_date.end_of_day)
    end
    logs
  end

  def period_label
    return "All records" unless params[:start_date].present? && params[:end_date].present?

    start_date = params[:start_date].to_date
    end_date = params[:end_date].to_date
    start_date == end_date ? start_date.strftime("%d %b %Y") : "#{start_date.strftime('%d %b %Y')} - #{end_date.strftime('%d %b %Y')}"
  end

  def export_filename(extension) = "operation-logs-#{Date.current}.#{extension}"
end
