class Admin::DashboardController < Admin::BaseController
  include FinancialFiltering

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
    # FinancialFiltering sets @start_date, @end_date, @date_preset
    
    @base_bookings = Booking.includes(:hotel).revenue_generating
                            .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
    
    if params[:q].present?
      @base_bookings = @base_bookings.joins(:hotel).where(
        "hotels.name ILIKE :q OR guest_name ILIKE :q OR confirmation_token ILIKE :q",
        q: "%#{params[:q]}%"
      )
    end

    @total_revenue = @base_bookings.sum(:total_amount)
    @total_margin = @base_bookings.sum("COALESCE(margin_amount, 0)")
    @total_net = @base_bookings.sum("COALESCE(net_amount, 0)")
    @booking_count = @base_bookings.count
    @active_hotels_count = @base_bookings.distinct.count(:hotel_id)

    @daily_rows = @base_bookings.group_by { |booking| booking.created_at.to_date }
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
