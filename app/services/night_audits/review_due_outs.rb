# frozen_string_literal: true

module NightAudits
  class ReviewDueOuts
    Result = Struct.new(:changed, :skipped, :failed, keyword_init: true)

    def self.call(night_audit:, user:)
      new(night_audit: night_audit, user: user).call
    end

    def initialize(night_audit:, user:)
      @night_audit = night_audit
      @hotel = night_audit.hotel
      @business_date = night_audit.business_date.to_date
      @user = user
      @changed = []
      @skipped = []
      @failed = []
    end

    def call
      candidates.find_each { |booking| review(booking) }
      Result.new(changed: @changed, skipped: @skipped, failed: @failed)
    end

    private

    def candidates
      cutoff = (@business_date + 1.day).in_time_zone(@hotel.hotel_time_zone).beginning_of_day
      @hotel.bookings.checked_in.where("check_out < ?", cutoff)
    end

    def review(booking)
      booking.with_lock do
        booking.reload

        unless eligible?(booking)
          @skipped << item_for(booking, reason: "Booking no longer qualifies for due-out review")
          next
        end

        result = Bookings::TransitionStatus.new(
          booking: booking,
          status: "review_due_out",
          user: @user,
          options: {
            event: "detect_late_checkout",
            source: "night_audit",
            reason: "Checkout date passed without checkout",
            metadata: {
              night_audit_id: @night_audit.id,
              business_date: @business_date.iso8601
            }
          }
        ).call

        if result.success?
          @changed << item_for(booking.reload, from: "checked_in", to: "review_due_out")
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
        "item_key" => "due_out_review:#{booking.id}:#{@business_date.iso8601}",
        "item_type" => "due_out_review",
        "booking_id" => booking.id,
        "confirmation_token" => booking.confirmation_token,
        "guest_name" => booking.guest_name,
        "check_out" => booking.check_out&.iso8601
      }.merge(attributes.stringify_keys)
    end
  end
end
