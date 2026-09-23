class Guest::DashboardController < Guest::BaseController
  before_action :authenticate_guest!

  def index
    @total_bookings = current_guest.bookings.count
    upcoming = current_guest.bookings.where("check_out::date >= ?", Date.current)
    @upcoming_count = upcoming.count
    @upcoming_bookings = upcoming
      .includes(:hotel, :booking_folios)
      .order(check_in: :asc)
      .limit(5)

    @past_bookings = current_guest.bookings
      .includes(:hotel, :booking_folios)
      .where("check_out::date < ?", Date.current)
      .order(check_in: :desc)
      .limit(5)
  end
end
