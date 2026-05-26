class HotelPortal::InHouseGuestsController < HotelPortal::BaseController
  def index
    @query = params[:query].to_s.strip
    @room_assignment = params[:room_assignment].to_s

    base_scope = current_hotel.bookings
                              .where(status: [ "checked_in", "review_due_out" ])
                              .where.not(checked_in_at: nil)
                              .where(checked_out_at: nil)

    @in_house_count = base_scope.count
    @check_outs_today_count = base_scope.where(check_out: Date.current).count

    in_house_scope = base_scope.includes(:booking_rooms, :guests, :booking_guests)

    if @query.present?
      search_term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      in_house_scope = in_house_scope.where(
        "guest_name ILIKE :search OR guest_email ILIKE :search OR guest_phone ILIKE :search OR confirmation_token ILIKE :search",
        search: search_term
      )
    end

    case @room_assignment
    when "assigned"
      in_house_scope = in_house_scope.left_outer_joins(:booking_rooms).where.not(booking_rooms: { id: nil }).distinct
    when "unassigned"
      in_house_scope = in_house_scope.left_outer_joins(:booking_rooms).where(booking_rooms: { id: nil })
    end

    @all_in_house_guests = in_house_scope.order(checked_in_at: :desc, created_at: :desc)
    @in_house_guests = @all_in_house_guests.page(params[:page]).per(25)
  end
end
