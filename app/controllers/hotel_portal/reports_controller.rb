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

    @bookings = hotel_bookings.created_between(@start_date, @end_date)
                             .search(params[:q])
                             .includes(booking_rooms: :room_type)
    @base_bookings = @bookings
    @daily_data = Booking.daily_revenue_data(@bookings)
  end

  def payouts
    cutoff_date = Booking.last_friday.end_of_day
    @active_tab = params[:tab] || "upcoming"

    @upcoming_bookings = current_hotel.bookings.unbatched_upcoming(cutoff_date)
    @upcoming_payout_amount = current_hotel.upcoming_payout_amount(cutoff_date)

    @processing_batches = current_hotel.payout_batches.where(status: "processing")

    @paid_start_date = parse_date_param(params[:paid_start_date])
    @paid_end_date = parse_date_param(params[:paid_end_date])

    @payout_history = current_hotel.payout_batches_for_reports(
      start_date: @paid_start_date,
      end_date: @paid_end_date
    ).page(params[:page]).per(25)
  end

  def breakdown
    @bookings = Booking.for_financial_breakdown(
      current_hotel,
      @start_date,
      @end_date,
      params[:q]
    )

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

  private

  def parse_date_param(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
