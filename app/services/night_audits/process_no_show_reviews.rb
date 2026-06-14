# frozen_string_literal: true

require "ostruct"

module NightAudits
  class ProcessNoShowReviews
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
      finalize_expired_reviews
      review_result = NightAudits::ReviewMissedArrivals.call(night_audit: @night_audit, user: @user)

      OpenStruct.new(
        success?: true,
        reviewed_count: review_result.reviewed_count,
        finalized_count: @finalized.count,
        reviewed_bookings: review_result.bookings,
        finalized_bookings: @finalized
      )
    end

    private

    def finalize_expired_reviews
      @hotel.bookings
        .where(status: "review_no_show")
        .where("no_show_review_business_date < ?", @business_date)
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
