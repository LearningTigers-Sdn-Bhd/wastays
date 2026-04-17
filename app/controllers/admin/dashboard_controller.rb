class Admin::DashboardController < Admin::BaseController
  def index
    @hotels_count = Hotel.count
    @pending_hotels_count = Hotel.where(status: "pending_review").count
    @total_bookings_count = Booking.revenue_generating.count
    @failed_webhooks_count = WebhookEvent.where(status: "failed").count

    @pending_hotels = Hotel.where(status: "pending_review").limit(5)
    @recent_bookings = Booking.revenue_generating.order(created_at: :desc).limit(5)
    @failed_webhooks = WebhookEvent.where(status: "failed").order(created_at: :desc).limit(5)

    current_month_bookings = Booking.revenue_generating.where(created_at: Time.current.all_month)
    @revenue_this_month = current_month_bookings.sum(:total_amount)
    @margin_this_month = current_month_bookings.sum("COALESCE(margin_amount, 0)")
  end

  def analytics
    @start_date = params[:start_date].present? ? params[:start_date].to_date : Date.current.beginning_of_month
    @end_date = params[:end_date].present? ? params[:end_date].to_date : Date.current.end_of_month
    @date_preset = params[:date_preset] || "custom"

    summary = Booking.analytics_summary(@start_date, @end_date, query: params[:q])
    @total_revenue = summary[:total_revenue]
    @total_margin = summary[:total_margin]
    @total_net = summary[:total_net]
    @booking_count = summary[:booking_count]
    @active_hotels_count = summary[:active_hotels_count]

    @daily_rows = Booking.daily_analytics(@start_date, @end_date, query: params[:q])
  end
end
