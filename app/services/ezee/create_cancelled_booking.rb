# frozen_string_literal: true

require "ostruct"

module Ezee
  # Records a reservation eZee released as a cancelled booking.
  #
  # The point of keeping it is the guest: staff can see a guest's past bookings,
  # cancelled ones included. So the booking and its guest are written, and
  # nothing else -- no room is held, no inventory is deducted, no folio is
  # opened, and nobody is notified or charged. It also cannot go through
  # Bookings::CreateManualBooking, which refuses a past arrival and checks
  # availability, neither of which means anything for a booking that holds no
  # room.
  #
  # Takes the same params as CreateManualBooking so the importer builds one set.
  class CreateCancelledBooking
    def initialize(hotel:, params:, user: nil)
      @hotel = hotel
      @params = params.dup
      @user = user
    end

    def call
      room_type = @hotel.room_types.find(@params.delete(:room_type_id))
      rate_plan = rate_plan_for(room_type, @params.delete(:rate_plan_id))
      @params.delete(:room_number)
      @params.delete(:require_room_number)
      normalize_stay_times!

      booking = @hotel.bookings.build(@params)
      booking.created_by_staff = true
      snapshot = financial_snapshot(booking, room_type, rate_plan)

      booking.total_amount = snapshot.room_total + Booking.non_tourism_tax_total_for(snapshot.tax_lines)
      booking.tax_lines = snapshot.tax_lines
      booking.tax_posting_snapshot = snapshot.tax_posting_snapshot
      booking.tourism_tax_amount = 0
      booking.tourism_tax_applied = false
      booking.tourism_tax_collected = false
      booking.status = "cancelled"
      booking.payment_status = "pending"
      booking.fund_collector = "hotel"
      booking.hotel_snapshot = @hotel.booking_snapshot

      Booking.transaction do
        booking.booking_rooms.build(
          room_type: room_type,
          rate_plan: rate_plan,
          subtotal: snapshot.room_total,
          room_type_snapshot: room_type.as_json,
          nightly_rate_snapshot: snapshot.nightly_rate_snapshot,
          occupancy_snapshot: { "adults" => booking.adults, "children" => booking.children, "child_ages" => [] }
        )
        booking.save!
        attach_guest(booking)
        Bookings::RecordAuditLog.call!(
          auditable: booking, user: @user, action_type: "create", source: "staff",
          metadata: { "imported_as" => "cancelled", "reason" => "Released in eZee" }
        )
      end

      OpenStruct.new(success?: true, booking: booking)
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError => e
      OpenStruct.new(success?: false, errors: [ e.message ])
    end

    private

    def rate_plan_for(room_type, rate_plan_id)
      (rate_plan_id && room_type.rate_plans.find_by(id: rate_plan_id)) || room_type.standard_rate_plan
    end

    def normalize_stay_times!
      %i[check_in check_out].each do |kind|
        next if @params[kind].blank?

        @params[kind] = Bookings::ScheduledStay.at_hotel_time(hotel: @hotel, value: @params[kind], kind: kind)
      end
    end

    def financial_snapshot(booking, room_type, rate_plan)
      Bookings::BuildFinancialSnapshot.new(
        hotel: @hotel, room_type: room_type, rate_plan: rate_plan,
        check_in: booking.check_in, check_out: booking.check_out,
        guest_country: nil, manual_total_amount: booking.manual_rate_override,
        adults: booking.adults, children: booking.children, child_ages: []
      ).call
    end

    # Every released reservation is its own guest: the export carries no email,
    # phone or document, and the per-reservation phone placeholder is what keeps
    # unrelated people from being merged.
    def attach_guest(booking)
      guest = Guest.create!(
        name: booking.guest_name, phone: booking.guest_phone,
        country: @hotel.country, created_by_hotel_id: @hotel.id
      )
      booking_guest = booking.booking_guests.create!(guest: guest, is_primary: true)
      BookingGuests::CapturePrimaryStay.call(booking_guest: booking_guest)
    end
  end
end
