# frozen_string_literal: true

require "ostruct"

module NightAudits
  module Processing
  class ProcessNoShowDetections
    def self.call(night_audit:, user:)
      new(night_audit: night_audit, user: user).call
    end

    def initialize(night_audit:, user:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @finalized = []
    end

    def call
      finalize_expired_detections
      detection_result = NightAudits::DetectMissedArrivals.call(night_audit: @night_audit, user: @user)

      OpenStruct.new(
        success?: true,
        no_show_detected_count: detection_result.detected_count,
        finalized_count: @finalized.count,
        detected_bookings: detection_result.bookings,
        finalized_bookings: @finalized
      )
    end

    private

    def finalize_expired_detections
      @hotel.bookings
        .where(status: "no_show_detected")
        .where("no_show_detected_business_date < ?", @business_date)
        .find_each do |booking|
          result = Bookings::FinalizeNoShow.call(
            booking: booking,
            user: @user,
            night_audit: @night_audit,
            automatic: true
          )
          raise result.error unless result.success?

          @finalized << booking
        end
    end
  end
  end
end
