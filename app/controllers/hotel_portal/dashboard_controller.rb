class HotelPortal::DashboardController < HotelPortal::BaseController
  def index
    @current_hotel = current_hotel
    unless @current_hotel
      redirect_to admin_hotels_path, alert: "Select a hotel before viewing the portal."
      return
    end

    if @current_hotel.onboarding?
      @upcoming_sessions = @current_hotel.onboarding_sessions.upcoming.order(:scheduled_at)
      render :onboarding and return
    end

    if @current_hotel.status == "pending_review"
      @upcoming_sessions = @current_hotel.onboarding_sessions.upcoming.order(:scheduled_at)
      render :pending_review and return
    end

    @today_arrivals = @current_hotel.bookings.active.where(check_in: Date.today)
    @tomorrow_arrivals = @current_hotel.bookings.active.where(check_in: Date.tomorrow)
    @today_checkouts = @current_hotel.bookings.active.where(check_out: Date.today)

    this_month = Time.current.beginning_of_month..Time.current.end_of_month
    @bookings_this_month_count = @current_hotel.bookings.active.where(created_at: this_month).count
    @revenue_this_month = @current_hotel.bookings.active.where(created_at: this_month).sum(:total_amount)

    arrival_window = Date.today..(Date.today + 1.day)
    @pending_actions_count = @current_hotel.bookings.active
      .joins(:pre_checkin)
      .where(pre_checkins: { status: "pending" })
      .where(check_in: arrival_window)
      .count

    setup_fee_override = SetupFeeRule.active.find_by(settable: @current_hotel)
    setup_fee_default = SetupFeeRule.active.where(settable_id: nil).find_by(settable_type: [ nil, "" ])
    active_setup_fee = setup_fee_override || setup_fee_default

    @setup_fee_amount = active_setup_fee&.amount&.to_f || 0.0
    @setup_fee_currency = active_setup_fee&.currency || SetupFeeRule::CURRENCY
    @setup_fee_source =
      if setup_fee_override
        "Hotel Override"
      elsif setup_fee_default
        "Global Default"
      else
        "Not Configured"
      end

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

  def onboarding_sessions
    @current_hotel = current_hotel
    unless @current_hotel
      redirect_to admin_hotels_path, alert: "Select a hotel before viewing the portal."
      return
    end

    @sessions = @current_hotel.onboarding_sessions
      .order(scheduled_at: :desc, created_at: :desc)
  end

  def cancel_onboarding_session
    @current_hotel = current_hotel
    unless @current_hotel
      redirect_to admin_hotels_path, alert: "Select a hotel before viewing the portal."
      return
    end

    @session = @current_hotel.onboarding_sessions.find(params[:session_id])

    unless @session.status == "scheduled"
      redirect_to hotel_onboarding_sessions_path(@current_hotel), alert: "Only scheduled sessions can be cancelled."
      return
    end

    cancel_reason = params[:cancel_reason].to_s.strip
    if cancel_reason.blank?
      redirect_to hotel_onboarding_sessions_path(@current_hotel), alert: "Please provide a reason before cancelling the session."
      return
    end

    @session.update!(
      status: "cancelled",
      notes: [ @session.notes.presence, "CANCELLED: #{cancel_reason}" ].compact.join("\n")
    )

    redirect_to hotel_onboarding_sessions_path(@current_hotel), notice: "Onboarding session cancelled."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to hotel_onboarding_sessions_path(@current_hotel), alert: "Failed to cancel session: #{e.message}"
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
