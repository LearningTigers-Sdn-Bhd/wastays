require "csv"

class HotelPortal::ReportsController < HotelPortal::BaseController
  include FinancialFiltering

  def index
    # Note: FinancialFiltering sets @start_date and @end_date
    hotel_bookings = current_hotel.bookings.revenue_generating

    summary = Booking.analytics_summary(@start_date, @end_date, query: params[:q], base_scope: hotel_bookings)
    @total_gross = summary[:total_revenue]
    @total_margin = summary[:total_margin]
    @total_net = summary[:total_net]
    @booking_count = summary[:booking_count]

    # Daily data for chart (simplified)
    @bookings = hotel_bookings.created_between(@start_date, @end_date).search(params[:q])
    @base_bookings = @bookings # Used in the view for daily calculations
    @daily_data = Booking.daily_revenue_data(@bookings)
  end

  def payouts
    cutoff_date = Booking.last_friday.end_of_day
    @active_tab = params[:tab] || "upcoming"

    @upcoming_bookings = current_hotel.bookings.unbatched_upcoming(cutoff_date)
    @upcoming_payout_amount = @upcoming_bookings.sum("COALESCE(net_amount, 0)")

    @processing_batches = current_hotel.payout_batches.where(status: "processing")

    # Apply pagination to history
    @payout_history = current_hotel.payout_batches.order(period_end: :desc).page(params[:page]).per(25)
  end

  def breakdown
    @base_bookings = current_hotel.bookings.revenue_generating
                             .where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
                             .order(created_at: :desc)

    @bookings = apply_search(@base_bookings, params[:q], %w[guest_name confirmation_token guest_email])

    respond_to do |format|
      format.html do
        @paginated_bookings = @bookings.page(params[:page]).per(25)
        @grouped_bookings = @paginated_bookings.group_by { |b| b.created_at.to_date }
      end
      format.csv do
        service = BookingExportService.new(@bookings)
        send_data service.generate_breakdown_csv, filename: "financial-breakdown-#{@start_date}-#{@end_date}.csv"
      end
    end
  end
end
