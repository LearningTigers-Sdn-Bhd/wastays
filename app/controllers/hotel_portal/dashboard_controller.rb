class HotelPortal::DashboardController < HotelPortal::BaseController
  def index
    @current_hotel = current_hotel
    unless @current_hotel
      redirect_to admin_hotels_path, alert: "Select a hotel before viewing the portal."
      return
    end

    if @current_hotel.onboarding?
      render :onboarding and return
    end

    if @current_hotel.status == "pending_review"
      render :pending_review and return
    end

    @today_arrivals = @current_hotel.bookings.active.where(check_in: Date.today)
    @tomorrow_arrivals = @current_hotel.bookings.active.where(check_in: Date.tomorrow)

    arrival_window = Date.today..(Date.today + 1.day)
    @pending_actions_count = @current_hotel.bookings.active
      .joins(:pre_checkin)
      .where(pre_checkins: { status: "pending" })
      .where(check_in: arrival_window)
      .count

    @recent_bookings = @current_hotel.bookings.order(created_at: :desc).limit(5)

    # 7-day occupancy snapshot (simplified for MVP)
    @occupancy_snapshot = (Date.today..(Date.today + 6.days)).map do |date|
      total_inventory = @current_hotel.room_types.joins(:room_inventories).where(room_inventories: { date: date }).sum(:quantity)
      rooms_sold = @current_hotel.bookings.revenue_generating.where(":date >= check_in AND :date < check_out", date: date).count
      {
        date: date,
        total: total_inventory,
        sold: rooms_sold,
        percent: total_inventory > 0 ? (rooms_sold.to_f / total_inventory * 100).round : 0
      }
    end
  end

  def submit_for_review
    @hotel = current_hotel
    authorize @hotel, :update?, policy_class: HotelPolicy

    if @hotel.submit_for_review!
      redirect_to hotel_dashboard_path, notice: "Your hotel has been submitted for review. We will contact you soon."
    else
      redirect_to hotel_dashboard_path, alert: "Please complete all onboarding steps before submitting."
    end
  end
end
