class HotelPortal::InventoryAuditLogsController < HotelPortal::BaseController
  def index
    redirect_to hotel_audit_logs_path(current_hotel, room_type_id: params[:room_type_id])
  end
end
