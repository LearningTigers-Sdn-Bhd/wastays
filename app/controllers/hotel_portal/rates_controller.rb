class HotelPortal::RatesController < HotelPortal::BaseController
  before_action :set_room_type
  before_action :set_rate_plan

  def index
    authorize current_hotel, :update?, policy_class: HotelPolicy
    @start_date = (params[:start_date] || Date.today).to_date
    @end_date = @start_date + 13.days # Show 2 weeks by default

    @rates = @rate_plan.room_rates.where(date: @start_date..@end_date).index_by(&:date)
  end

  def create
    authorize current_hotel, :update?, policy_class: HotelPolicy

    result = HotelOps::BulkUpdateRates.new(
      hotel: current_hotel,
      rate_plan: @rate_plan,
      start_date: rate_params[:start_date],
      end_date: rate_params[:end_date],
      price: rate_params[:price],
      currency: rate_params[:currency],
      user: current_user
    ).call

    if result[:success]
      redirect_to hotel_room_type_rates_path(current_hotel, @room_type, start_date: rate_params[:start_date]), notice: "Rates updated successfully."
    else
      redirect_to hotel_room_type_rates_path(current_hotel, @room_type), alert: "Error updating rates: #{result[:error]}"
    end
  end

  private

  def set_room_type
    @room_type = current_hotel.room_types.find(params[:room_type_id])
  end

  def set_rate_plan
    # Default to the first rate plan for now.
    # In the future, this can be passed in params[:rate_plan_id]
    @rate_plan = @room_type.rate_plans.first || @room_type.rate_plans.create!(name: "Standard Rate", currency: @room_type.hotel.default_currency || "MYR")
  end

  def rate_params
    params.require(:rate).permit(:start_date, :end_date, :price, :currency)
  end
end
