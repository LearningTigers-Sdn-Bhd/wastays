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
      @rate_plan_id = @params.delete(:rate_plan_id)
      @user = user
      @override = override
      @override_reason = override_reason
    end

    def call
      return OpenStruct.new(success?: false, errors: [ "Status cannot be changed through stay update." ]) if @params.key?(:status)

      failure_error = nil
      assigned_room_number = extract_assigned_room_number
      result = nil

      result = ActiveRecord::Base.transaction do
        # 1. Store old state for inventory management and change detection
        old_check_in = @booking.check_in
        old_check_out = @booking.check_out
        current_room = @booking.booking_rooms.first
        old_room_type_id = current_room&.room_type_id
        old_rate_plan_id = current_room&.rate_plan_id

        # 2. Update Booking attributes (including dates and any other params)
        if @booking.update(@params)
          new_check_in = @booking.check_in
          new_check_out = @booking.check_out

          dates_changing = old_check_in != new_check_in || old_check_out != new_check_out
          room_type_changing = @room_type_id.present? && @room_type_id.to_i != old_room_type_id
          rate_plan_changing = @rate_plan_id.present? && @rate_plan_id.to_i != old_rate_plan_id

          # 3. Handle Financial and Inventory Changes if anything relevant changed
          if dates_changing || room_type_changing || rate_plan_changing
            # Release old inventory using old dates and old room type
            InventoryManager.new(@booking).release_by_dates(old_check_in, old_check_out)

            # Determine new room type and rate plan
            new_room_type = room_type_changing ? @hotel.room_types.find(@room_type_id) : current_room&.room_type
            new_rate_plan = @rate_plan_id.present? ? @hotel.rate_plans.find(@rate_plan_id) : current_room&.rate_plan

            # Recalculate Price using BuildFinancialSnapshot (includes taxes)
            financial_snapshot = BuildFinancialSnapshot.new(
              hotel: @hotel,
              check_in: new_check_in,
              check_out: new_check_out,
              guest_country: @booking.guest_country,
              room_type: new_room_type,
              rate_plan: new_rate_plan,
              manual_total_amount: @booking.manual_rate_override
            ).call

            # Update the booking room
            if current_room
              current_room.update!(
                room_type: new_room_type,
                room_type_snapshot: new_room_type.as_json,
                rate_plan: new_rate_plan,
                subtotal: financial_snapshot.room_total,
                nightly_rate_snapshot: financial_snapshot.nightly_rate_snapshot
              )
            end

            # Update booking totals (including taxes)
            @booking.update_columns(
              total_amount: financial_snapshot.room_total + financial_snapshot.tax_total,
              tax_lines: financial_snapshot.tax_lines,
              tax_posting_snapshot: financial_snapshot.tax_posting_snapshot,
              tourism_tax_amount: financial_snapshot.tax_lines.find { |t| t["type"] == "tourism_tax" }&.fetch("amount", 0).to_d,
              tourism_tax_applied: financial_snapshot.tax_lines.any? { |t| t["type"] == "tourism_tax" }
            )

            # Deduct new inventory
            InventoryManager.new(@booking).deduct
          end

          # 4. Handle Room Assignment if room number changed or dates changed
          target_room_number = assigned_room_number.presence || @booking.hotel_snapshot&.dig("room_number")
          if target_room_number.present? && (assigned_room_number.present? || dates_changing)
            # Check for locks by others if assigning a NEW room
            if assigned_room_number.present?
              lock = @hotel.room_locks.active.find_by(room_number: assigned_room_number)
              if lock && lock.user_id != @user&.id
                raise "Room #{assigned_room_number} is currently being assigned by another staff member"
              end
            end

            # Verify availability for target room
            active_room_type = room_type_changing ? new_room_type : current_room&.room_type
            if active_room_type
              available_service = Bookings::AvailableRoomNumbers.new(
                hotel: @hotel,
                room_type: active_room_type,
                check_in: new_check_in,
                check_out: new_check_out,
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

          # Record Audit Log
          Bookings::RecordAuditLog.call(
            auditable: @booking,
            user: @user,
            action_type: "update"
          )

          sync_guest(@booking)
          Notifications::Dispatcher.new(event: :booking_updated, booking: @booking).call if dates_changing
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
