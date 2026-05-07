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
        rooms: @booking.booking_rooms.map do |br|
          {
            room_type: br.room_type.name,
            quantity: br.quantity,
            subtotal: br.subtotal.to_f,
            room_number: br.room_number
          }
        end,
        created_at: @booking.created_at,
        updated_at: @booking.updated_at
      }
    end
  end
end
