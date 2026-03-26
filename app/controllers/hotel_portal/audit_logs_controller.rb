require 'csv'

class HotelPortal::AuditLogsController < HotelPortal::BaseController
  def index
    @logs = current_hotel.inventory_audit_logs.includes(:room_type, :user).order(created_at: :desc)

    # Filtering
    @logs = @logs.where(room_type_id: params[:room_type_id]) if params[:room_type_id].present?
    @logs = @logs.where(action_type: params[:action_type]) if params[:action_type].present?
    
    if params[:start_date].present? && params[:end_date].present?
      @logs = @logs.where(created_at: params[:start_date].to_date.beginning_of_day..params[:end_date].to_date.end_of_day)
    end

    respond_to do |format|
      format.html { @logs = @logs.page(params[:page]).per(20) }
      format.csv { send_data generate_csv(@logs), filename: "audit-logs-#{Date.today}.csv" }
    end
  end

  private

  def generate_csv(logs)
    attributes = %w[id action_type room_type user created_at old_value new_value]

    CSV.generate(headers: true) do |csv|
      csv << attributes

      logs.each do |log|
        csv << [
          log.id,
          log.action_type.titleize,
          log.room_type&.name || 'N/A',
          log.user.name,
          log.created_at.strftime("%Y-%m-%d %H:%M:%S"),
          log.old_value.to_json,
          log.new_value.to_json
        ]
      end
    end
  end
end
