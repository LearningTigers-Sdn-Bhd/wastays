# frozen_string_literal: true

require "ostruct"

module Bookings
  class ReinstateReservation
    ReinstatementFailure = Class.new(StandardError)

    def initialize(booking:, params:, user:, options: {})
      @booking = booking
      @params = params
      @user = user
      @options = options
    end

    def call
      NightAudits::OperationalChangeGuard.call!(hotel: @booking.hotel, action: :reinstate)
      return OpenStruct.new(success?: false, error: "Only no-show bookings can be reinstated.") unless @booking.status == "no_show"

      Booking.transaction do
        @booking.with_lock do
          @booking.reload

          # 1. Update room assignment, category, and selected rate before catch-up charges are posted.
          apply_room_changes

          # 2. Validate availability for the remaining stay
          unless rooms_available?
            raise ReinstatementFailure, "One or more assigned rooms are not available for the remaining stay."
          end

          # 3. Reserve inventory (released by no-show)
          # We need to reserve from today (current business date) until check-out
          business_date = @booking.hotel.current_business_date
          Bookings::InventoryManager.new(@booking).reserve_by_dates(business_date, @booking.check_out.to_date)

          # 4. Reopen folios that were closed automatically during no-show finalization.
          Folios::Lifecycle::ReopenNoShowFoliosForReinstatement.call(booking: @booking, user: @user)

          # 5. Transition status to checked_in
          guest_registration = if @booking.guest_registration_number.present?
            year = @booking.guest_registration_year || DocumentIdentifiers::Issuer.sequence_year(hotel: @booking.hotel)
            DocumentIdentifiers::Issuer::Allocation.new(
              number: @booking.guest_registration_number,
              year:,
              reference: @booking.guest_registration_reference || DocumentIdentifiers::Issuer.format(
                hotel: @booking.hotel,
                type: :guest_registration,
                year:,
                number: @booking.guest_registration_number
              )
            )
          else
            DocumentIdentifiers::Issuer.issue!(hotel: @booking.hotel, type: :guest_registration)
          end
          @booking.transition_status_to!(
            "checked_in",
            event: "reinstate",
            attributes: {
              checked_in_at: Time.current,
              guest_registration_number: guest_registration.number,
              guest_registration_year: guest_registration.year,
              guest_registration_reference: guest_registration.reference
            }
          )

          # 6. Initialize Folio if needed and process catch-up charges
          Folios::Lifecycle::InitializeForBooking.call(booking: @booking, user: @user, options: @options, lock: false)
          Folios::Charges::ProcessCatchUpCharges.call(booking: @booking, user: @user, is_reinstate: true)

          # 7. Audit Log
          metadata = {
            retroactive_checkin: true,
            retroactive_reason: @options[:reason],
            reinstated: true
          }
          Bookings::RecordAuditLog.call!(
            auditable: @booking,
            user: @user,
            action_type: "reinstate",
            old_value: { "status" => "no_show" },
            new_value: { "status" => "checked_in", "checked_in_at" => @booking.checked_in_at },
            reason: @options[:reason],
            metadata: metadata.merge("room_number" => @booking.booking_rooms.first&.room_number)
          )
        end
      end

      OpenStruct.new(success?: true)
    rescue ReinstatementFailure => e
      OpenStruct.new(success?: false, error: e.message)
    rescue StandardError => e
      OpenStruct.new(success?: false, error: e.message)
    end

    private

    def apply_room_changes
      return if booking_room_attributes.blank?

      booking_room_attributes.each do |attributes|
        booking_room = @booking.booking_rooms.find(attributes[:id])
        room_type = room_type_for(attributes, booking_room)
        rate_plan = rate_plan_for(attributes, room_type, booking_room)
        room_number = attributes[:room_number].presence || booking_room.room_number

        booking_room.update!(
          room_type: room_type,
          rate_plan: rate_plan,
          room_number: room_number,
          subtotal: subtotal_for(room_type, rate_plan),
          room_type_snapshot: room_type.as_json
        )
      end

      @booking.reload
      @booking.hotel_snapshot ||= {}
      if @booking.booking_rooms.first&.room_number.present?
        @booking.hotel_snapshot = @booking.hotel_snapshot.merge("room_number" => @booking.booking_rooms.first.room_number)
      end
      @booking.update!(total_amount: @booking.booking_rooms.sum(:subtotal))
    end

    def rooms_available?
      business_date = @booking.hotel.current_business_date
      return @booking.booking_rooms.all? { |booking_room| booking_room.room_number.present? } if @booking.check_out.to_date <= business_date

      @booking.booking_rooms.all? do |booking_room|
        next false if booking_room.room_number.blank?

        service = Bookings::AvailableRoomNumbers.new(
          hotel: @booking.hotel,
          room_type: booking_room.room_type,
          check_in: business_date,
          check_out: @booking.check_out,
          exclude_booking_id: @booking.id
        )

        service.call.include?(booking_room.room_number.to_s)
      end
    end

    def booking_room_attributes
      raw_attributes = @params[:booking_rooms_attributes]
      return [] if raw_attributes.blank?

      attributes = raw_attributes.respond_to?(:to_unsafe_h) ? raw_attributes.to_unsafe_h : raw_attributes
      attributes = attributes.values if attributes.is_a?(Hash)
      Array(attributes).map { |room_attributes| room_attributes.to_h.symbolize_keys }
    end

    def room_type_for(attributes, booking_room)
      room_type_id = attributes[:room_type_id].presence || booking_room.room_type_id
      @booking.hotel.room_types.find(room_type_id)
    end

    def rate_plan_for(attributes, room_type, booking_room)
      if attributes[:rate_plan_id].blank?
        # Check if the existing rate plan is still valid for the (potentially new) room type
        if booking_room.rate_plan&.archived_at.nil? && room_type.room_type_rate_plans.exists?(rate_plan_id: booking_room.rate_plan_id)
          return booking_room.rate_plan
        end

        return room_type.standard_rate_plan
      end

      room_type.rate_plans.active.find(attributes[:rate_plan_id])
    rescue ActiveRecord::RecordNotFound
      raise "Selected rate is not available for the selected room category."
    end

    def subtotal_for(room_type, rate_plan)
      subtotal = Bookings::CalculateStayPrice.new(
        room_type: room_type,
        rate_plan: rate_plan,
        check_in: @booking.check_in,
        check_out: @booking.check_out,
        adults: @booking.adults,
        children: @booking.children
      ).call

      # Reinstating re-prices the stay at today's rates. If a night no longer
      # has a price for this party, the reservation cannot be reinstated at a
      # total we can stand behind — the alternative is reinstating it at zero.
      raise "This stay no longer has a price for every night. Set the missing rates and try again." if subtotal.nil?

      subtotal
    end
  end
end
