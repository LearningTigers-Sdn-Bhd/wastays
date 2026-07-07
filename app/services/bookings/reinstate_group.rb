# frozen_string_literal: true

require "ostruct"

module Bookings
  class ReinstateGroup
    BatchFailure = Class.new(StandardError)

    def self.call(group_booking:, booking_attributes:, user:, options: {})
      new(group_booking: group_booking, booking_attributes: booking_attributes, user: user, options: options).call
    end

    def initialize(group_booking:, booking_attributes:, user:, options: {})
      @group_booking = group_booking
      @booking_attributes = booking_attributes.to_h.stringify_keys
      @user = user
      @options = options
    end

    def call
      bookings = selected_bookings
      validate_batch!(bookings)

      ActiveRecord::Base.transaction do
        bookings.each do |booking|
          result = ReinstateReservation.new(
            booking: booking,
            params: @booking_attributes.fetch(booking.id.to_s),
            user: @user,
            options: @options
          ).call
          raise BatchFailure, result.error unless result.success?
        end
      end

      OpenStruct.new(success?: true, bookings: bookings, error: nil)
    rescue BatchFailure, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
      OpenStruct.new(success?: false, bookings: [], error: e.message)
    end

    private

    def selected_bookings
      ids = @booking_attributes.keys.filter_map { |id| Integer(id, exception: false) }.uniq
      raise BatchFailure, "Select at least one booking." if ids.empty?

      bookings = @group_booking.bookings.includes(booking_rooms: :room_type).where(id: ids).order(:group_position, :id).to_a
      raise BatchFailure, "One or more selected bookings are not part of this group." unless bookings.size == ids.size

      bookings
    end

    def validate_batch!(bookings)
      raise BatchFailure, "Reason for reinstatement is required." if @options[:reason].blank?

      stale = bookings.reject { |booking| booking.status == "no_show" }
      raise BatchFailure, "One or more selected bookings are no longer eligible for reinstatement." if stale.any?

      assignments = bookings.flat_map do |booking|
        room_attributes_for(booking).map do |attributes|
          room = booking.booking_rooms.find { |candidate| candidate.id == attributes[:id].to_i }
          raise BatchFailure, "Every selected booking requires a valid room assignment." unless room

          room_number = attributes[:room_number].to_s.strip
          room_type_id = attributes[:room_type_id].presence || room.room_type_id
          raise BatchFailure, "Every selected booking requires a room category and room number." if room_type_id.blank? || room_number.blank?

          [ room_type_id.to_s, room_number ]
        end
      end

      raise BatchFailure, "The same room cannot be assigned to more than one selected booking." if assignments.uniq.size != assignments.size
    end

    def room_attributes_for(booking)
      raw = @booking_attributes.fetch(booking.id.to_s).to_h.with_indifferent_access[:booking_rooms_attributes]
      raw = raw.values if raw.is_a?(Hash)
      attributes = Array(raw).map { |value| value.to_h.symbolize_keys }
      raise BatchFailure, "Every selected booking must be configured before reinstatement." if attributes.empty?

      attributes
    end
  end
end
