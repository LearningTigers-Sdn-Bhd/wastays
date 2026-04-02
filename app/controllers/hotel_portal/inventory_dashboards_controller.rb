class HotelPortal::InventoryDashboardsController < HotelPortal::BaseController
  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy

    @start_date = (params[:start_date] || Date.today).to_date
    @end_date = @start_date + 13.days # Show 14 days by default

    @room_types = current_hotel.room_types.includes(:room_inventories, :room_rates)

    # Pre-fetch inventory and rates for the date range
    @inventory_matrix = {}
    @rates_matrix = {}

    @room_types.each do |rt|
      @inventory_matrix[rt.id] = rt.room_inventories.where(date: @start_date..@end_date).index_by(&:date)
      @rates_matrix[rt.id] = rt.room_rates.where(date: @start_date..@end_date).index_by(&:date)
    end
  end

  def create
    authorize current_hotel, :update?, policy_class: HotelPolicy

    result = HotelOps::BulkUpdateRatesAndInventory.new(
      hotel: current_hotel,
      room_type_ids: bulk_update_params[:room_type_ids],
      start_date: bulk_update_params[:start_date],
      end_date: bulk_update_params[:end_date],
      price: bulk_update_params[:price],
      quantity: bulk_update_params[:quantity],
      status: bulk_update_params[:status],
      user: current_user
    ).call

    if result[:success]
      redirect_to hotel_inventory_index_path(current_hotel, start_date: bulk_update_params[:start_date]), notice: "Bulk update applied successfully."
    else
      redirect_to hotel_inventory_index_path(current_hotel), alert: "Error during bulk update: #{result[:error]}"
    end
  end

  private

  def bulk_update_params
    params.require(:bulk_update).permit(:start_date, :end_date, :price, :quantity, :status, room_type_ids: [])
  end
end
