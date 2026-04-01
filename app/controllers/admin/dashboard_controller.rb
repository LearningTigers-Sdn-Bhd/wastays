class Admin::DashboardController < Admin::BaseController
  def index
    @hotels_count = Hotel.count
    @pending_hotels_count = Hotel.where(status: "pending_review").count
    @total_bookings_count = Booking.revenue_generating.count
    @failed_webhooks_count = WebhookEvent.where(status: "failed").count

    @pending_hotels = Hotel.where(status: "pending_review").limit(5)
    @recent_bookings = Booking.revenue_generating.order(created_at: :desc).limit(5)
    @failed_webhooks = WebhookEvent.where(status: "failed").order(created_at: :desc).limit(5)

    # Simple revenue/margin calculation for MVP
    @revenue_this_month = Booking.revenue_generating.where(created_at: Time.current.all_month).sum(:total_amount)
    @margin_this_month = Booking.revenue_generating.where(created_at: Time.current.all_month).sum(:margin_amount)
  end
end
