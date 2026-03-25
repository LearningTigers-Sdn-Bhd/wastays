class Hotel::InventoryAuditLogsController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!

  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy
    @audit_logs = current_hotel.inventory_audit_logs.includes(:room_type, :user).order(created_at: :desc).page(params[:page]).per(20)
  end
end
