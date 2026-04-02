class HotelPortal::InventoriesController < HotelPortal::BaseController
  before_action :set_room_type

  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy
    @start_date = (params[:start_date] || Date.today).to_date
    @end_date = @start_date + 13.days

    @inventories = @room_type.room_inventories.where(date: @start_date..@end_date).index_by(&:date)
  end

  def create
    authorize current_hotel, :update?, policy_class: HotelPolicy

    result = HotelOps::BulkUpdateInventory.new(
      hotel: current_hotel,
      room_type: @room_type,
      start_date: inventory_params[:start_date],
      end_date: inventory_params[:end_date],
      quantity: inventory_params[:quantity],
      status: inventory_params[:status],
      user: current_user
    ).call

    if result[:success]
      redirect_to hotel_room_type_inventories_path(current_hotel, @room_type, start_date: inventory_params[:start_date]), notice: "Inventory updated successfully."
    else
      redirect_to hotel_room_type_inventories_path(current_hotel, @room_type), alert: "Error updating inventory: #{result[:error]}"
    end
  end

  private

  def set_room_type
    @room_type = current_hotel.room_types.find(params[:room_type_id])
  end

  def inventory_params
    params.require(:inventory).permit(:start_date, :end_date, :quantity, :status)
  end
end
