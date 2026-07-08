# frozen_string_literal: true

class HotelPortal::DashboardController < HotelPortal::BaseController
  def index
    @current_hotel = current_hotel
    unless @current_hotel
      redirect_to admin_hotels_path, alert: "Select a hotel before viewing the portal."
      return
    end

    if @current_hotel.status == "pending_review"
      render :pending_review and return
    end

    # Role-based redirection
    if current_user.has_permission?("view_reports", hotel: @current_hotel) && !current_user.has_permission?("manage_guest_arrival", hotel: @current_hotel)
      redirect_to hotel_reports_path(@current_hotel) and return
    elsif current_user.has_permission?("manage_room_status", hotel: @current_hotel) && !current_user.has_permission?("manage_guest_arrival", hotel: @current_hotel)
      redirect_to hotel_room_status_board_path(@current_hotel) and return
    end

    stats = HotelPortal::DashboardStats.new(@current_hotel)
    @today_arrivals = stats.today_arrivals
    @tomorrow_arrivals = stats.tomorrow_arrivals
    @today_checkouts = stats.today_checkouts
    @bookings_this_month_count = stats.bookings_this_month_count
    @revenue_this_month = stats.revenue_this_month
    @pending_actions_count = stats.pending_actions_count
    @occupancy_snapshot = stats.occupancy_snapshot
    @live_inventory = stats.live_inventory

    @active_setup_fee = @current_hotel.active_setup_fee
    @setup_fee_amount = @active_setup_fee&.amount&.to_f || 0.0
    @setup_fee_currency = @active_setup_fee&.currency || SetupFeeRule::CURRENCY
    @setup_fee_source = @current_hotel.setup_fee_source

    @recent_bookings = @current_hotel.bookings.order(created_at: :desc).limit(5).includes(booking_guests: :guest)

    @dashboard_presenter = HotelPortal::DashboardPresenter.new(@current_hotel, stats, @recent_bookings)
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
