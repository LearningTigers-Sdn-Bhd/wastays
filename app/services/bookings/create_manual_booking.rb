# frozen_string_literal: true

require "ostruct"

module Bookings
  class CreateManualBooking
    def initialize(hotel:, params:, user: nil)
      @hotel = hotel
      @params = params.dup
      @room_type_id = @params.delete(:room_type_id)
      @room_number = @params.delete(:room_number)
      @user = user
    end

    def call
      booking = @hotel.bookings.build(@params)
      room_type = @hotel.room_types.find(@room_type_id)
      failure_error = nil
      result = nil

      # 1. Validate Room Availability based on Grid Selection
      available_rooms = AvailableRoomNumbers.new(
        hotel: @hotel,
        room_type: room_type,
        check_in: booking.check_in,
        check_out: booking.check_out
      ).call

      unless available_rooms.include?(@room_number.to_s)
        return OpenStruct.new(success?: false, errors: [ "Room #{@room_number} is no longer available for these dates." ])
      end

      # 1.1 Check for locks by others
      lock = @hotel.room_locks.active.find_by(room_number: @room_number)
      if lock && lock.user_id != Current.user_id
        return OpenStruct.new(success?: false, errors: [ "Room #{@room_number} is currently being assigned by another staff member." ])
      end

      # 2. Calculate accurate total amount from Grid Rates
      booking.total_amount = (booking.check_in..(booking.check_out - 1.day)).sum do |date|
        rate = room_type.room_rates.find_by(date: date)
        rate&.price || room_type.base_price
      end

      booking.status = "confirmed"
      booking.payment_status = "captured"
      booking.hotel_snapshot = @hotel.booking_snapshot.merge("room_number" => @room_number)

      result = ActiveRecord::Base.transaction do
        if booking.save
          booking.booking_rooms.create!(
            room_type: room_type,
            quantity: 1,
            subtotal: booking.total_amount,
            room_type_snapshot: room_type.as_json
          )

          assignment_result = Bookings::AssignRoom.new(
            booking: booking,
            room_number: @room_number,
            user: @user
          ).call

          unless assignment_result.success?
            failure_error = assignment_result.error
            raise ActiveRecord::Rollback
          end

          InventoryManager.new(booking).deduct
          sync_guest(booking)

          # Record Audit Log
          Bookings::RecordAuditLog.call(
            auditable: booking,
            user: @user,
            action_type: "create"
          )

          # Trigger Webhooks
          Bookings::WebhookTriggerService.new(booking).trigger(:booking_confirmed)
          Notifications::Dispatcher.new(event: :booking_confirmed, booking: booking).call

          # Trigger Channex CRS Sync if connected
          if @hotel.preferred_channel_manager.present?
            adapter = ChannelManagers::SyncOrchestrator.adapter_for(@hotel)
            adapter.push_booking(booking)
          end

          OpenStruct.new(success?: true, booking: booking)
        else
          OpenStruct.new(success?: false, errors: booking.errors.full_messages)
        end
      end
      return OpenStruct.new(success?: false, errors: [ failure_error ]) if failure_error.present?
      result
    rescue => e
      OpenStruct.new(success?: false, errors: [ e.message ])
    end

    private

    def sync_guest(booking)
      guest_result = GuestArrival::CreateOrMatchGuest.new(
        name: booking.guest_name,
        email: booking.guest_email,
        phone: booking.guest_phone,
        country: booking.guest_country.presence || @hotel.country,
        created_by_hotel_id: @hotel.id
      ).call

      if guest_result.success? && !booking.booking_guests.exists?(guest: guest_result.guest)
        booking.booking_guests.create!(guest: guest_result.guest, is_primary: true)
      end
    end
  end
end
