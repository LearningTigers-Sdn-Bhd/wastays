class Guest::DashboardController < Guest::BaseController
  before_action :authenticate_guest!

  def index
    @total_bookings = current_guest.bookings.count
    @upcoming_bookings = current_guest.bookings
      .where("check_out::date >= ?", Date.current)
      .order(check_in: :asc)
      .limit(5)

    @past_bookings = current_guest.bookings
      .where("check_out::date < ?", Date.current)
      .order(check_in: :desc)
      .limit(5)
  end
end
