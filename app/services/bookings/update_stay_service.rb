# frozen_string_literal: true

require "ostruct"

module Bookings
  class UpdateStayService
    def initialize(booking:, params:, user: nil, override: false, override_reason: nil)
      @booking = booking
      @hotel = booking.hotel
      @params = params.dup
      @room_type_id = @params.delete(:room_type_id)
      @room_number = @params.delete(:room_number)
      @user = user
      @override = override
      @override_reason = override_reason
    end

    def call
      failure_error = nil
      assigned_room_number = extract_assigned_room_number
      result = nil

      result = ActiveRecord::Base.transaction do
        # 1. Handle Room Type / Inventory Change
        if @room_type_id.present?
          new_room_type = @hotel.room_types.find(@room_type_id)
          current_room = @booking.booking_rooms.first

          if current_room && current_room.room_type_id != new_room_type.id
            # Release old inventory
            InventoryManager.new(@booking).release

            # Update or replace the booking room
            current_room.update!(
              room_type: new_room_type,
              room_type_snapshot: new_room_type.as_json,
              subtotal: new_room_type.base_price * (@booking.check_out - @booking.check_in).to_i
            )
          end
        end

        # 2. Check for occupancy overlap if room is assigned or dates are changing
        check_in = @params[:check_in].presence ? Date.parse(@params[:check_in].to_s) : @booking.check_in
        check_out = @params[:check_out].presence ? Date.parse(@params[:check_out].to_s) : @booking.check_out
        dates_changing = check_in != @booking.check_in || check_out != @booking.check_out
        target_room_number = assigned_room_number.presence || @booking.hotel_snapshot&.dig("room_number")

        if target_room_number.present? && (assigned_room_number.present? || dates_changing)
          # Check for locks by others if assigning a NEW room
          if assigned_room_number.present?
            lock = @hotel.room_locks.active.find_by(room_number: assigned_room_number)
            if lock && lock.user_id != @user&.id
              raise "Room #{assigned_room_number} is currently being assigned by another staff member"
            end
          end

          room_type_id = @room_type_id.presence || @booking.booking_rooms.first&.room_type_id

          if room_type_id.present?
            room_type = @hotel.room_types.find(room_type_id)
            available_service = Bookings::AvailableRoomNumbers.new(
              hotel: @hotel,
              room_type: room_type,
              check_in: check_in,
              check_out: check_out,
              exclude_booking_id: @booking.id
            )

            unless available_service.call.include?(target_room_number.to_s)
              options = available_service.options
              option = options.find { |o| o[:room_number].to_s == target_room_number.to_s }
              reason = option ? option[:label].split("(").last.gsub(")", "") : "Occupied"
              raise "Room #{target_room_number} is not available for these dates: #{reason}"
            end
          end

          if assigned_room_number.present?
            @booking.hotel_snapshot ||= {}
            @booking.hotel_snapshot = @booking.hotel_snapshot.merge("room_number" => assigned_room_number)
          end
        end

        # 3. Save main booking details
        old_dates = { check_in: @booking.check_in, check_out: @booking.check_out }

        if @booking.update(@params)
          dates_changed = old_dates[:check_in] != @booking.check_in || old_dates[:check_out] != @booking.check_out

          # 4. If dates changed or room type changed, sync inventory
          if dates_changed || @room_type_id.present?
            # If only dates changed but not room type, we still need to release and re-deduct
            # Note: if room type changed, we already released old ones above.
            # But release_by_dates is safer if only dates changed.
            # If room type changed, release was already called on OLD room type.

            if @room_type_id.blank? # Only dates changed
               InventoryManager.new(@booking).release_by_dates(old_dates[:check_in], old_dates[:check_out])
            end

            InventoryManager.new(@booking).deduct
          end

          if assigned_room_number.present?
            assignment_result = Bookings::AssignRoom.new(
              booking: @booking,
              room_number: assigned_room_number,
              user: @user,
              override: @override,
              override_reason: @override_reason
            ).call

            unless assignment_result.success?
              failure_error = assignment_result.error
              raise ActiveRecord::Rollback
            end
          end

          sync_guest(@booking)
          Notifications::Dispatcher.new(event: :booking_updated, booking: @booking).call if dates_changed
          OpenStruct.new(success?: true, booking: @booking)
        else
          OpenStruct.new(success?: false, errors: @booking.errors.full_messages)
        end
      end
      return OpenStruct.new(success?: false, errors: [ failure_error ]) if failure_error.present?
      result
    rescue => e
      OpenStruct.new(success?: false, errors: [ e.message ])
    end

    private

    def extract_assigned_room_number
      from_nested_params = @params.dig(:booking_rooms_attributes, "0", :room_number) ||
        @params.dig(:booking_rooms_attributes, 0, :room_number)

      if @params[:booking_rooms_attributes].is_a?(ActionController::Parameters) || @params[:booking_rooms_attributes].is_a?(Hash)
        @params[:booking_rooms_attributes].each_value do |attributes|
          next unless attributes.respond_to?(:delete)

          attributes.delete(:room_number)
        end
      end

      @room_number.presence || from_nested_params.presence
    end

    def sync_guest(booking)
      guest_result = GuestArrival::CreateOrMatchGuest.new(
        name: booking.guest_name,
        email: booking.guest_email,
        phone: booking.guest_phone,
        country: booking.guest_country.presence || @hotel.country,
        created_by_hotel_id: @hotel.id
      ).call

      if guest_result.success? && !booking.booking_guests.exists?(guest: guest_result.guest)
        # If email changed, we might have multiple guests linked?
        # For now, let's just ensure the primary guest is updated if it matches the new email
        # or create a new link if none exists.

        # Remove old primary if it exists and we're adding a new one?
        # Actually, standardizing on one primary guest per booking.
        booking.booking_guests.where(is_primary: true).destroy_all
        booking.booking_guests.create!(guest: guest_result.guest, is_primary: true)
      end
    end
  end
end
