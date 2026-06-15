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
      normalize_scheduled_stay!
      guard_financially_relevant_change!

      failure_error = nil
      assigned_room_number = extract_assigned_room_number
      result = nil

      result = ActiveRecord::Base.transaction do
        old_audit_values = audit_values
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
            @booking.update!(
              total_amount: financial_snapshot.room_total + financial_snapshot.tax_total,
              tax_lines: financial_snapshot.tax_lines,
              tax_posting_snapshot: financial_snapshot.tax_posting_snapshot,
              tourism_tax_amount: financial_snapshot.tax_lines.find { |t| t["type"] == "tourism_tax" }&.fetch("amount", 0).to_d,
              tourism_tax_applied: financial_snapshot.tax_lines.any? { |t| t["type"] == "tourism_tax" }
            )

            # Deduct new inventory
            InventoryManager.new(@booking).deduct

            # Reconcile forecasts against the changed stay without recreating already-posted nights.
            if @booking.booking_folio.present?
              Folios::SyncForecastedCharges.call(booking_folio: @booking.booking_folio)
            end
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
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "update",
            old_value: old_audit_values,
            new_value: audit_values,
            reason: @override_reason.presence
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

    FINANCIALLY_RELEVANT_FIELDS = %w[
      check_in check_out total_amount manual_rate_override tax_lines tax_posting_snapshot
      tourism_tax_amount tourism_tax_applied payment_status guarantee_method
    ].freeze

    def guard_financially_relevant_change!
      return unless financially_relevant_change_requested?

      NightAudits::OperationalChangeGuard.call!(hotel: @hotel, action: :update_stay)
    end

    def financially_relevant_change_requested?
      current_room = @booking.booking_rooms.first
      return true if @room_type_id.present? && @room_type_id.to_i != current_room&.room_type_id
      return true if @rate_plan_id.present? && @rate_plan_id.to_i != current_room&.rate_plan_id
      return true if changed_booking_financial_field?

      nested_rooms = @params[:booking_rooms_attributes] || @params["booking_rooms_attributes"]
      return false unless nested_rooms.respond_to?(:each_value)

      nested_rooms.each_value.any? do |attributes|
        room_attributes = attributes.to_h.stringify_keys
        booking_room = @booking.booking_rooms.find { |room| room.id == room_attributes["id"].to_i } || current_room
        (room_attributes["room_type_id"].present? && room_attributes["room_type_id"].to_i != booking_room&.room_type_id) ||
          (room_attributes["rate_plan_id"].present? && room_attributes["rate_plan_id"].to_i != booking_room&.rate_plan_id)
      end
    end

    def changed_booking_financial_field?
      FINANCIALLY_RELEVANT_FIELDS.any? do |field|
        next false unless @params.key?(field.to_sym) || @params.key?(field)

        requested_value = @params.key?(field.to_sym) ? @params[field.to_sym] : @params[field]
        cast_value = @booking.class.type_for_attribute(field).cast(requested_value)
        @booking.public_send(field) != cast_value
      end
    end

    def audit_values
      room = @booking.booking_rooms.first
      @booking.attributes.slice(
        "guest_name", "guest_email", "guest_phone", "guest_country", "check_in", "check_out",
        "adults", "children", "total_amount", "payment_status", "guarantee_method"
      ).merge(
        "room_category" => room&.room_type&.name,
        "rate_plan" => room&.rate_plan&.name,
        "room_number" => room&.room_number
      )
    end

    def normalize_scheduled_stay!
      %i[check_in check_out].each do |kind|
        next if @params[kind].blank?

        @params[kind] = ScheduledStay.at_hotel_time(hotel: @hotel, value: @params[kind], kind: kind)
      end
    end

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
