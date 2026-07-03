# frozen_string_literal: true

module BookingAuditable
  extend ActiveSupport::Concern

  private

  def set_audit_logs(booking, group_booking: nil)
    base_query = BookingAuditLog.where(hotel: current_hotel)
    bookings = group_booking ? group_booking.bookings : Booking.where(id: booking.id)
    booking_ids = bookings.select(:id)
    quote_ids = bookings.where.not(booking_quote_id: nil).select(:booking_quote_id)
    room_ids = BookingRoom.where(booking_id: booking_ids).select(:id)

    @audit_logs = base_query.where(auditable_type: "Booking", auditable_id: booking_ids)
      .or(base_query.where(auditable_type: "BookingQuote", auditable_id: quote_ids))
      .or(base_query.where(auditable_type: "BookingRoom", auditable_id: room_ids))
      .includes(:user, :auditable)
      .order(occurred_at: :desc, created_at: :desc)
    @audit_history = @audit_logs.map { |log| HotelPortal::BookingAuditLogPresenter.new(log, hotel: current_hotel) }
  end
end
