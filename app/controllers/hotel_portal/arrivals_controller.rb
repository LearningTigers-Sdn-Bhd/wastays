class HotelPortal::ArrivalsController < HotelPortal::BaseController
  def index
    @date = params[:date].present? ? Date.parse(params[:date]) : Date.today
    @query = params[:q].to_s.strip

    arrivals_scope = current_hotel.bookings
                                  .active
                                  .where(check_in: @date)
                                  .includes(:booking_rooms, :pre_checkin, :booking_guests, :guests)

    if @query.present?
      search_term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      arrivals_scope = arrivals_scope.where(
        "guest_name ILIKE :search OR guest_email ILIKE :search OR guest_phone ILIKE :search OR confirmation_token ILIKE :search",
        search: search_term
      )
    end

    @all_arrivals = arrivals_scope.order(created_at: :asc)
    @arrivals = @all_arrivals.page(params[:page]).per(25)

    @today_count = current_hotel.bookings.active.where(check_in: Date.today).count
    @tomorrow_count = current_hotel.bookings.active.where(check_in: Date.tomorrow).count
  end
end
