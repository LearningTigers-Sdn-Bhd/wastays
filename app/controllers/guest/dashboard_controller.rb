class Guest::DashboardController < Guest::BaseController
  before_action :authenticate_guest!

  def index
    bookings = current_guest.bookings
    groups = Guest::StatusBadges::BOOKING_GROUPS
    booked = groups.fetch("pending") + groups.fetch("confirmed")
    in_house = groups.fetch("checked_in")

    # Upcoming is a live booking that has not started. In house is a guest
    # checked in now. A cancelled stay counts toward the total only.
    @stats = {
      total: bookings.count,
      upcoming: bookings.where(status: booked).where("check_in::date >= ?", Date.current).count,
      in_house: bookings.where(status: in_house).count,
      refunds: RefundRequest.where(booking: bookings).count
    }

    @next_stay = bookings.includes(:hotel)
      .where(status: booked + in_house)
      .where("check_out::date >= ?", Date.current)
      .order(:check_in, :id)
      .first

    @recent_bookings = bookings.includes(:hotel, :booking_folios)
      .where.not(id: @next_stay&.id)
      .order(check_in: :desc, id: :desc)
      .limit(4)
  end
end
