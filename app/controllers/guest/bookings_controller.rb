class Guest::BookingsController < Guest::BaseController
  before_action :authenticate_guest!

  def index
    @bookings = current_guest.bookings.includes(:hotel).order(check_in: :desc)
  end

  def show
    @booking = current_guest.bookings.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to guest_bookings_path, alert: "Booking not found."
  end
end
