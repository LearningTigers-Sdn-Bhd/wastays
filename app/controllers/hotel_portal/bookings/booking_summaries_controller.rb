# frozen_string_literal: true

class HotelPortal::Bookings::BookingSummariesController < HotelPortal::BaseController
  before_action :authorize_manage_bookings!
  before_action :set_booking

  # A group settles one position, so a group has one summary. Staff reach a room far more
  # often than they reach the group, so a room resolving up to its group is the ordinary
  # path here rather than an edge case.
  def show
    pdf_bytes = if @booking.group_booking
      Reports::Bookings::GenerateBookingSummary.new(group_booking: @booking.group_booking).generate
    else
      Reports::Bookings::GenerateBookingSummary.new(booking: @booking).generate
    end

    send_data pdf_bytes,
      filename: "wastays-booking-summary-#{summary_reference}.pdf",
      type: "application/pdf",
      disposition: "inline"
  end

  private

  def summary_reference
    (@booking.group_booking || @booking).confirmation_token
  end

  def set_booking
    @booking = current_hotel.bookings.includes(:group_booking).find(params[:booking_id])
  end

  def authorize_manage_bookings!
    raise Pundit::NotAuthorizedError unless current_user.has_permission?("manage_bookings", hotel: current_hotel)
  end
end
