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

    @bookings = Booking.includes(:hotel).revenue_generating.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    @total_revenue = @bookings.sum(:total_amount)
    @total_margin = @bookings.sum("COALESCE(margin_amount, 0)")
    @total_net = @bookings.sum("COALESCE(net_amount, 0)")
    @booking_count = @bookings.count
    @active_hotels_count = @bookings.distinct.count(:hotel_id)
    @daily_rows = @bookings.group_by { |booking| booking.created_at.to_date }
                          .sort
                          .map do |date, bookings|
      {
        date: date,
        booking_count: bookings.count,
        revenue: bookings.sum(&:total_amount),
        margin: bookings.sum { |booking| booking.margin_amount || 0 },
        net: bookings.sum { |booking| booking.net_amount || 0 }
      }
    end
  end
end
