require "csv"

class HotelPortal::ReportsController < HotelPortal::BaseController
  include FinancialFiltering

  def index
    # Note: FinancialFiltering sets @start_date and @end_date
    @base_bookings = current_hotel.bookings.revenue_generating.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)

    @bookings = apply_search(@base_bookings, params[:q], %w[guest_name confirmation_token guest_email])

    # Aggregates (on full filtered scope without pagination)
    @total_gross = @bookings.sum(:total_amount) || 0
    @total_margin = @bookings.sum("COALESCE(margin_amount, 0)")
    @total_net = @bookings.sum("COALESCE(net_amount, 0)")
    @booking_count = @bookings.count

    # Daily data for chart (simplified)
    @daily_data = @bookings.group_by { |b| b.created_at.to_date }
                           .transform_values { |bs| bs.sum(&:total_amount) }
                           .sort.to_h
  end

  def payouts
    cutoff_date = Booking.last_friday.end_of_day
    @active_tab = params[:tab] || "upcoming"
    @upcoming_bookings = current_hotel.bookings.completed
                                      .where(payout_batch_id: nil)
                                      .where("checked_out_at > ?", cutoff_date)
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
      format.csv { send_data generate_breakdown_csv(@bookings), filename: "financial-breakdown-#{@start_date}-#{@end_date}.csv" }
    end
  end

  private

  def generate_breakdown_csv(bookings)
    attributes = %w[confirmation_token guest_name status check_in check_out total_amount margin_rate margin_amount net_amount currency]

    CSV.generate(headers: true) do |csv|
      csv << attributes.map(&:titleize)

      bookings.each do |booking|
        csv << [
          booking.confirmation_token,
          booking.guest_name,
          booking.status,
          booking.check_in,
          booking.check_out,
          booking.total_amount,
          booking.margin_rate,
          booking.margin_amount,
          booking.net_amount,
          booking.currency
        ]
      end
    end
  end
end
