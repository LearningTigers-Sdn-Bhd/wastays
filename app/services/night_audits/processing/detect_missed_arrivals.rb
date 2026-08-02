# frozen_string_literal: true

require "ostruct"

module NightAudits
  module Processing
  class DetectMissedArrivals
    def self.call(night_audit:, user:)
      new(night_audit: night_audit, user: user).call
    end

    def initialize(night_audit:, user:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @detected = []
      @hotel_zone = Time.find_zone(@hotel.time_zone.presence || User::DEFAULT_TIME_ZONE) || Time.zone
    end

    def call
      candidates.find_each { |booking| detect(booking) }
      OpenStruct.new(success?: true, detected_count: @detected.count, bookings: @detected)
    end

    private

    def candidates
      @hotel.bookings.confirmed
        .includes(:pre_checkin)
        .checking_in_on(@business_date, @hotel.hotel_time_zone)
    end

    def detect(booking)
      Booking.transaction do
        booking.with_lock do
          booking.reload
          next unless eligible?(booking)

          booking.transition_status_to!(
            "no_show_detected",
            event: "detect_no_show",
            attributes: { no_show_detected_business_date: @business_date }
          )
          Bookings::RecordAuditLog.call!(
            auditable: booking,
            user: @user,
            action_type: "status_change",
            source: "night_audit",
            old_value: { "status" => "confirmed" },
            new_value: { "status" => "no_show_detected" },
            metadata: {
              from: "confirmed",
              to: "no_show_detected",
              event: "detect_no_show",
              night_audit_id: @night_audit.id,
              business_date: @business_date.iso8601
            }
          )
          @detected << booking
        end
      end
    end

    def eligible?(booking)
      booking.status == "confirmed" &&
        booking_local_date(booking.check_in) == @business_date &&
        !active_pre_checkin_hold?(booking)
    end

    def active_pre_checkin_hold?(booking)
      pre_checkin = booking.pre_checkin
      return false unless pre_checkin&.completed?

      declared_arrival_at = declared_arrival_at_for(booking, pre_checkin)
      declared_arrival_at && audit_reference_time < declared_arrival_at + @hotel.arrival_grace_period.seconds
    end

    def declared_arrival_at_for(booking, pre_checkin)
      arrival_time = pre_checkin.metadata&.fetch("estimated_arrival_time", nil).presence
      return nil unless arrival_time

      hour, minute = arrival_time.to_s.split(":").first(2).map(&:to_i)
      return nil unless hour&.between?(0, 23) && minute&.between?(0, 59)

      arrival_date = booking_local_date(booking.check_in)
      if business_day_crosses_midnight? && seconds_since_midnight(hour, minute) <= seconds_since_midnight(@hotel.business_ends_at.hour, @hotel.business_ends_at.min)
        arrival_date += 1.day
      end
      @hotel_zone.local(arrival_date.year, arrival_date.month, arrival_date.day, hour, minute)
    end

    def audit_reference_time
      @audit_reference_time ||= (@night_audit.completed_at || @night_audit.started_at || Time.current).in_time_zone(@hotel_zone)
    end

    def business_day_crosses_midnight?
      @hotel.business_ends_at <= @hotel.business_starts_at
    end

    def seconds_since_midnight(hour, minute)
      (hour * 3600) + (minute * 60)
    end

    def booking_local_date(value)
      Bookings::ScheduledStay.local_date(hotel: @hotel, value: value)
    end
  end
  end
end
