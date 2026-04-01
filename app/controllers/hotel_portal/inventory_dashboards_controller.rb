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
end
