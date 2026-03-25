class Hotel::RatesController < ApplicationController
  before_action :authenticate_user!
  before_action :ensure_hotel_access!
  before_action :set_room_type

  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy
    @start_date = (params[:start_date] || Date.today).to_date
    @end_date = @start_date + 13.days # Show 2 weeks by default
    
    @rates = @room_type.room_rates.where(date: @start_date..@end_date).index_by(&:date)
  end

  def create
    authorize current_hotel, :update?, policy_class: HotelPolicy
    
    result = HotelOps::BulkUpdateRates.new(
      hotel: current_hotel,
      room_type: @room_type,
      start_date: rate_params[:start_date],
      end_date: rate_params[:end_date],
      price: rate_params[:price],
      currency: rate_params[:currency],
      user: current_user
    ).call

    if result[:success]
      redirect_to hotel_room_type_rates_path(@room_type, start_date: rate_params[:start_date]), notice: "Rates updated successfully."
    else
      redirect_to hotel_room_type_rates_path(@room_type), alert: "Error updating rates: #{result[:error]}"
    end
  end

  private

  def set_room_type
    @room_type = current_hotel.room_types.find(params[:room_type_id])
  end

  def rate_params
    params.require(:rate).permit(:start_date, :end_date, :price, :currency)
  end
end
