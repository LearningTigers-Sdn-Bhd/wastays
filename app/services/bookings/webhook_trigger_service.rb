# frozen_string_literal: true

module Bookings
  class WebhookTriggerService
    def initialize(booking)
      @booking = booking
    end

    def trigger(event_type)
      payload = build_payload(event_type)
      WebhookBroadcastJob.perform_later(event_type.to_s, payload)
    end

    private

    def build_payload(event_type)
      {
        booking_id: @booking.id,
        confirmation_token: @booking.confirmation_token,
        status: @booking.status,
        payment_status: @booking.payment_status,
        guest: {
          name: @booking.guest_name,
          email: @booking.guest_email,
          phone: @booking.guest_phone,
          country: @booking.guest_country
        },
        stay: {
          check_in: @booking.check_in,
          check_out: @booking.check_out,
          adults: @booking.adults,
          children: @booking.children,
          total_amount: @booking.total_amount.to_f,
          currency: @booking.currency
        },
        hotel: {
          id: @booking.hotel_id,
          name: @booking.hotel.name
        },
        rooms: @booking.booking_rooms.group_by(&:room_type_id).map do |room_type_id, rooms|
          first_room = rooms.first
          {
            room_type: first_room.room_type.name,
            quantity: rooms.size,
            subtotal: rooms.sum { |r| r.subtotal.to_f }.round(2),
            room_number: rooms.map(&:room_number).compact.presence&.join(", ")
          }
        end,
        created_at: @booking.created_at,
        updated_at: @booking.updated_at
      }
    end
  end
end
