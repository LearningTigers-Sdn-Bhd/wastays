class HotelPortal::ArrivalsController < HotelPortal::BaseController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @arrivals = current_hotel.bookings
                             .active
                             .where(check_in: @date)
                             .includes(:booking_rooms, :pre_checkin, :booking_guests, :guests)
                             .order(created_at: :asc)

    @today_count = current_hotel.bookings.active.where(check_in: Date.today).count
    @tomorrow_count = current_hotel.bookings.active.where(check_in: Date.tomorrow).count
  end
end
