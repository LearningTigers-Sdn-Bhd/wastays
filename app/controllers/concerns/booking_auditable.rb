# frozen_string_literal: true

module BookingAuditable
  extend ActiveSupport::Concern

  private

  def set_audit_logs(booking)
    base_query = BookingAuditLog.where(hotel: current_hotel)
    @audit_logs = base_query.where(auditable: booking)

    if booking.booking_quote_id.present?
      @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingQuote", auditable_id: booking.booking_quote_id))
    end

    @audit_logs = @audit_logs.or(base_query.where(auditable_type: "BookingRoom", auditable_id: booking.booking_rooms.select(:id)))
                            .includes(:user, :auditable)
                            .order(created_at: :desc)
  end
end
