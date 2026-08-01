# frozen_string_literal: true

module NightAudits
  class DetectDueOuts
    Result = Struct.new(:detected, :skipped, :failed, keyword_init: true)

    def self.call(night_audit:, user:)
      new(night_audit: night_audit, user: user).call
    end

    def initialize(night_audit:, user:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @detected = []
      @skipped = []
      @failed = []
    end

    def call
      candidates.find_each { |booking| detect(booking) }
      Result.new(detected: @detected, skipped: @skipped, failed: @failed)
    end

    private

    def candidates
      cutoff = (@business_date + 1.day).in_time_zone(@hotel.hotel_time_zone).beginning_of_day
      @hotel.bookings.checked_in.where("check_out < ?", cutoff)
    end

    def detect(booking)
      booking.with_lock do
        booking.reload

        unless eligible?(booking)
          @skipped << item_for(booking, reason: "Booking no longer qualifies for due-out detection")
          next
        end

        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "due_out_detected",
          user: @user,
          options: {
            event: "detect_due_out",
            source: "night_audit",
            reason: "Checkout date passed without checkout",
            night_audit: @night_audit,
            metadata: {
              night_audit_id: @night_audit.id,
              business_date: @business_date.iso8601
            }
          }
        ).call

        if result.success?
          @detected << item_for(booking.reload, from: "checked_in", to: "due_out_detected")
        else
          @failed << item_for(booking, reason: result.error)
        end
      end
    rescue StandardError => e
      @failed << item_for(booking, reason: e.message)
    end

    def eligible?(booking)
      booking.status == "checked_in" &&
        booking.check_out.in_time_zone(@hotel.hotel_time_zone).to_date <= @business_date
    end

    def item_for(booking, attributes = {})
      {
        "item_key" => "due_out_detection:#{booking.id}:#{@business_date.iso8601}",
        "item_type" => "due_out_detection",
        "booking_id" => booking.id,
        "confirmation_token" => booking.confirmation_token,
        "guest_name" => booking.guest_name,
        "check_out" => booking.check_out&.iso8601
      }.merge(attributes.stringify_keys)
    end
  end
end
