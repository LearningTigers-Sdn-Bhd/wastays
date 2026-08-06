# frozen_string_literal: true

module BookingAuditable
  extend ActiveSupport::Concern

  AUDIT_FILTER_CATEGORIES = %w[all status stay room financial notes].freeze

  private

  def set_audit_logs(booking, group_booking: nil, category: params[:category])
    base_query = BookingAuditLog.where(hotel: current_hotel)
    bookings = group_booking ? group_booking.bookings : Booking.where(id: booking.id)
    booking_ids = bookings.select(:id)
    quote_ids = bookings.where.not(booking_quote_id: nil).select(:booking_quote_id)
    room_ids = BookingRoom.where(booking_id: booking_ids).select(:id)

    audit_scope = base_query.where(auditable_type: "Booking", auditable_id: booking_ids)
      .or(base_query.where(auditable_type: "BookingQuote", auditable_id: quote_ids))
      .or(base_query.where(auditable_type: "BookingRoom", auditable_id: room_ids))

    @audit_category = category.to_s.presence_in(AUDIT_FILTER_CATEGORIES) || "all"
    @audit_history_available = audit_scope.exists?
    audit_scope = audit_scope.where(category: @audit_category) unless @audit_category == "all"

    @audit_logs = audit_scope
      .includes(:user, :auditable)
      .order(occurred_at: :desc, created_at: :desc)
    @audit_history = @audit_logs.map { |log| HotelPortal::BookingAuditLogPresenter.new(log, hotel: current_hotel) }
  end
end
