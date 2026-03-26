class Hotel::InventoryAuditLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def index
    redirect_to hotel_audit_logs_path(room_type_id: params[:room_type_id])
  end
end
