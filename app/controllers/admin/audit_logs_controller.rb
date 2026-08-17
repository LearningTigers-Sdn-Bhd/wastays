class Admin::AuditLogsController < Admin::BaseController
  def index
    @logs = InventoryAuditLog.includes(:hotel, :room_type, :user).order(created_at: :desc)

    # Filtering
    @logs = @logs.where(hotel_id: params[:hotel_id]) if params[:hotel_id].present?
    if params[:action_type].present?
      action_types = case params[:action_type]
                     when "bulk_rate_update", "rate_update"
                       %w[bulk_rate_update rate_update]
                     when "bulk_inventory_update", "inventory_update"
                       %w[bulk_inventory_update inventory_update]
                     else
                       params[:action_type]
                     end
      @logs = @logs.where(action_type: action_types)
    end

    if params[:start_date].present? && params[:end_date].present?
      @logs = @logs.where(created_at: params[:start_date].to_date.beginning_of_day..params[:end_date].to_date.end_of_day)
    end

    @logs = @logs.page(params[:page]).per(20)
    @hotels = Hotel.all.order(:name)
  end
end
