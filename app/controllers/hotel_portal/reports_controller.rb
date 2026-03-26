class HotelPortal::ReportsController < HotelPortal::BaseController
  def index
    @start_date = params[:start_date].present? ? params[:start_date].to_date : Date.today.beginning_of_month
    @end_date = params[:end_date].present? ? params[:end_date].to_date : Date.today.end_of_month

    @bookings = current_hotel.bookings.revenue_generating.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)

    # Aggregates
    @total_gross = @bookings.sum(:total_amount) || 0
    @total_margin = @bookings.sum("COALESCE(margin_amount, 0)")
    @total_net = @bookings.sum("COALESCE(net_amount, 0)")
    @booking_count = @bookings.count

    # Daily data for chart (simplified)
    @daily_data = @bookings.group_by { |b| b.created_at.to_date }
                           .transform_values { |bs| bs.sum(&:total_amount) }
                           .sort.to_h
  end
end
