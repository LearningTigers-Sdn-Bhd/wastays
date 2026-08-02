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
      @failed = []
      context = NightAudits::Evaluation::Context.new(hotel: @hotel, business_date: @business_date, phase: :pre_close)
      @eligibility = NightAudits::Evaluation::OverdueGuestStays.new(context: context)
    end

    def call
      candidates.each { |booking| detect(booking) }
      OpenStruct.new(success?: @failed.empty?, detected_count: @detected.count, bookings: @detected, failed: @failed)
    end

    private

    def candidates
      @eligibility.confirmed_missed_arrivals
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
    rescue StandardError => error
      @failed << item_for(booking, reason: error.message)
    end

    def eligible?(booking)
      @eligibility.confirmed_missed_arrival?(booking)
    end

    def item_for(booking, attributes = {})
      {
        "item_key" => "missed_arrival_detection:#{booking.id}:#{@business_date.iso8601}",
        "item_type" => "missed_arrival_detection",
        "booking_id" => booking.id,
        "confirmation_token" => booking.confirmation_token,
        "guest_name" => booking.guest_name,
        "check_in" => booking.check_in&.iso8601
      }.merge(attributes.stringify_keys)
    end
  end
  end
end
