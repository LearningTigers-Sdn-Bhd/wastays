class Admin::PayoutsController < Admin::BaseController
  before_action :set_breadcrumbs, only: [ :index ]

  def index
    # Friday cutoff logic (Friday end of day)
    cutoff_date = Booking.last_friday.end_of_day

    @eligible_bookings = Booking.completed
                                .where(payout_status: "pending")
                                .where("checked_out_at <= ?", cutoff_date)

    @payout_summary = Booking.payout_summary_by_hotel(@eligible_bookings)
    @payout_summary = Kaminari.paginate_array(@payout_summary).page(params[:page]).per(25)
  end

  def export_payouts_csv
    cutoff_date = Booking.last_friday.end_of_day
    bookings_to_process = Booking.completed
                                 .where(payout_status: "pending")
                                 .where("checked_out_at <= ?", cutoff_date)

    if bookings_to_process.empty?
      redirect_to admin_payouts_path, alert: "No eligible bookings for payout."
      return
    end

    service = PayoutExportService.new(bookings_to_process, type: :bookings)
    csv_data = service.generate_csv

    send_data csv_data, filename: "Payout_#{Date.current}.csv", type: "text/csv"
  end

  def mark_as_paid
    cutoff_date = Booking.last_friday.end_of_day
    reference = "PAY-#{SecureRandom.hex(4).upcase}"

    Booking.transaction do
      bookings = Booking.completed
                        .where(payout_status: "pending")
                        .where("checked_out_at <= ?", cutoff_date)

      bookings.update_all(
        payout_status: "paid",
        payout_at: Time.current,
        payout_reference: reference
      )
    end

    redirect_to admin_payouts_path, notice: "Selected bookings marked as paid with reference: #{reference}"
  end

  private

  def set_breadcrumbs
    override_breadcrumbs(
      { label: "Finance" },
      { label: "Payouts", path: admin_payouts_path }
    )
  end
end
