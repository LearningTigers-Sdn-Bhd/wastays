class Admin::DashboardController < Admin::BaseController
  include FinancialFiltering

  def index
    live_bookings = Booking.joins(:hotel).where(hotels: { status: "live" }).revenue_generating
    @hotels_count = Hotel.count
    @pending_hotels_count = Hotel.where(status: "pending_review").count
    @total_bookings_count = live_bookings.count
    @failed_webhooks_count = WebhookEvent.where(status: "failed").count

    @pending_hotels = Hotel.where(status: "pending_review").limit(5)
    @recent_bookings = live_bookings.order(created_at: :desc).limit(5)
    @failed_webhooks = WebhookEvent.where(status: "failed").order(created_at: :desc).limit(5)

    current_month_bookings = live_bookings.where(created_at: Time.current.all_month)
    @revenue_this_month = current_month_bookings.sum(:total_amount)
    @margin_this_month = current_month_bookings.sum("COALESCE(margin_amount, 0)")
  end

  def analytics
    live_bookings = Booking.joins(:hotel).where(hotels: { status: "live" }).revenue_generating
    summary = Booking.analytics_summary(@start_date, @end_date, query: params[:q], base_scope: live_bookings)
    @total_revenue = summary[:total_revenue]
    @total_margin = summary[:total_margin]
    @total_net = summary[:total_net]
    @booking_count = summary[:booking_count]
    @active_hotels_count = summary[:active_hotels_count]

    @daily_rows = Booking.daily_analytics(@start_date, @end_date, query: params[:q], base_scope: live_bookings)
  end
end
