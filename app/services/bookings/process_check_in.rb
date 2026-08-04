# frozen_string_literal: true

require "digest"
require "ostruct"

module Bookings
  class ProcessCheckIn
    class CheckInError < StandardError; end

    def initialize(bookings:, details:, user:, source: nil)
      @bookings = Array(bookings)
      @details = details.to_h
      @user = user
      @source = source
      @editing = @bookings.first&.status == "checked_in"
    end

    def call
      validate_request!
      transitioned = []
      committed = false

      ActiveRecord::Base.transaction do
        @bookings.sort_by(&:id).each(&:lock!)
        validate_current_statuses!
        transitioned = @bookings.select { |booking| booking.status == "confirmed" }
        lock_requested_rooms!
        @bookings.each { |booking| validate_details!(booking) }
        @bookings.each do |booking|
          result = transition(booking)
          raise CheckInError, booking_error(booking, result.error) unless result.success?
          apply_boat_times!(booking)
        end
      end
      committed = true

      transitioned.each { |booking| dispatch_checked_in(booking) }
      success
    rescue CheckInError, ArgumentError, Date::Error => e
      failure(e.message)
    ensure
      release_room_locks if committed
    end

    private

    def validate_request!
      raise CheckInError, "Select at least one booking." if @bookings.empty?

      statuses = @bookings.map(&:status).uniq
      unless statuses.one? && statuses.first.in?(%w[confirmed checked_in])
        raise CheckInError, "Selected bookings are no longer eligible for check-in."
      end
    end

    def validate_current_statuses!
      expected_status = editing? ? "checked_in" : "confirmed"
      return if @bookings.all? { |booking| booking.status == expected_status }

      raise CheckInError, "Selected bookings are no longer eligible for check-in."
    end

    def validate_details!(booking)
      details = details_for(booking)
      reason = details[:reason].to_s.strip
      raise CheckInError, booking_error(booking, "Reason to change is required.") if editing? && reason.blank?
      raise CheckInError, booking_error(booking, "Check-in date and time is required.") if details[:checked_in_at].blank?

      timestamp_for(booking)
      validate_security_deposit!(booking)
      validate_rooms!(booking)
    end

    def validate_security_deposit!(booking)
      deposit = details_for(booking)[:security_deposit]
      return if deposit.blank?
      raise CheckInError, booking_error(booking, "Security deposits cannot be collected while editing check-in details.") if editing?

      amount = deposit[:amount].to_d
      unless amount.positive?
        raise CheckInError, booking_error(booking, "Security deposit amount must be greater than zero.")
      end

      method_result = PaymentMethods::Eligibility.call(
        hotel: booking.hotel,
        id: deposit[:hotel_payment_method_id],
        purpose: :direct
      )
      raise CheckInError, booking_error(booking, method_result.error) unless method_result.success?
    end

    def validate_rooms!(booking)
      booking.booking_rooms.each do |booking_room|
        room_number = submitted_room_number(booking, booking_room)
        if room_number.blank?
          raise CheckInError, booking_error(booking, "Assign every room before checking in.")
        end

        configured_rooms = booking_room.room_type.room_numbers.map(&:to_s)
        unless room_number.in?(configured_rooms)
          raise CheckInError, booking_error(booking, "Room #{room_number} does not belong to #{booking_room.room_type.name}.")
        end

        available = AvailableRoomNumbers.new(
          hotel: booking.hotel,
          room_type: booking_room.room_type,
          check_in: booking.check_in,
          check_out: booking.check_out,
          exclude_booking_id: booking.id
        ).call.map(&:to_s)
        unless room_number.in?(available)
          raise CheckInError, booking_error(booking, "Room #{room_number} is no longer available for this stay.")
        end
      end
    end

    def lock_requested_rooms!
      room_keys = @bookings.flat_map do |booking|
        booking.booking_rooms.map do |booking_room|
          room_number = submitted_room_number(booking, booking_room)
          [ booking.hotel_id, booking_room.room_type_id, room_number ] if room_number.present?
        end
      end.compact.uniq.sort

      room_keys.each do |key|
        lock_id = Digest::SHA256.digest(key.join(":"))[0, 8].unpack1("q>")
        ActiveRecord::Base.connection.exec_query(
          "SELECT 1 AS acquired FROM pg_advisory_xact_lock($1)",
          "advisory_lock",
          [ lock_id ]
        )
      end
    end

    def submitted_room_number(booking, booking_room)
      assignments = details_for(booking)[:room_assignments].to_h
      return booking_room.room_number.to_s.strip unless assignments.key?(booking_room.id.to_s)

      assignments[booking_room.id.to_s].to_s.strip
    end

    def transition(booking)
      details = details_for(booking)
      reason = details[:reason].to_s.strip
      override_night_audit = ActiveModel::Type::Boolean.new.cast(details[:override_night_audit])
      options = { source: @source, defer_side_effects: true }
      options[:reason] = reason if editing? || override_night_audit
      options[:override_night_audit] = true if override_night_audit

      attributes = booking_attributes(booking)
      options[:attributes] = attributes if attributes.present?
      options[:security_deposit] = details[:security_deposit] if details[:security_deposit].present?

      TransitionStatus.new(
        booking: booking,
        status: "checked_in",
        timestamp: timestamp_for(booking),
        user: @user,
        options: options
      ).call
    end

    def apply_boat_times!(booking)
      Boats::AssignTimes.call(booking: booking, params: details_for(booking))
    rescue ActiveRecord::RecordInvalid => e
      raise CheckInError, booking_error(booking, e.record.errors.full_messages.to_sentence)
    end

    def booking_attributes(booking)
      details = details_for(booking)
      attributes = {}
      unless details[:tourism_tax_collected].nil?
        attributes[:tourism_tax_collected] = ActiveModel::Type::Boolean.new.cast(details[:tourism_tax_collected])
      end

      assignments = booking.booking_rooms.filter_map do |booking_room|
        next unless details[:room_assignments].to_h.key?(booking_room.id.to_s)

        { id: booking_room.id, room_number: submitted_room_number(booking, booking_room) }
      end
      attributes[:booking_rooms_attributes] = assignments if assignments.any?
      attributes
    end

    def details_for(_booking)
      @details
    end

    def timestamp_for(booking)
      @timestamps ||= {}
      @timestamps[booking.id] ||= ScheduledStay.at_hotel_time(
        hotel: booking.hotel,
        value: details_for(booking)[:checked_in_at],
        kind: :check_in
      )
    end

    def editing?
      @editing
    end

    def dispatch_checked_in(booking)
      dispatch_nonfatal(booking, "webhook") do
        Bookings::WebhookTriggerService.new(booking).trigger(:booking_checked_in)
      end
      dispatch_nonfatal(booking, "notification") do
        Notifications::Dispatcher.new(event: :booking_checked_in, booking: booking).call
      end
    end

    def dispatch_nonfatal(booking, kind)
      yield
    rescue StandardError => e
      Rails.logger.error("Failed to dispatch check-in #{kind} for booking #{booking.id}: #{e.class}: #{e.message}")
    end

    def release_room_locks
      @bookings.each do |booking|
        booking.booking_rooms.each do |booking_room|
          RoomLock.where(
            hotel: booking.hotel,
            user: @user,
            room_type: booking_room.room_type,
            room_number: booking_room.room_number
          ).destroy_all
        end
      end
    rescue StandardError => e
      Rails.logger.error("Failed to release check-in room locks: #{e.class}: #{e.message}")
    end

    def booking_error(booking, message)
      return message if @bookings.one?

      "#{booking.guest_name.presence || booking.confirmation_token}: #{message}"
    end

    def success
      OpenStruct.new(success?: true, bookings: @bookings)
    end

    def failure(error)
      OpenStruct.new(success?: false, error: error, bookings: @bookings)
    end
  end
end
