# frozen_string_literal: true

module NightAudits
  module Execution
    class ClaimBusinessDate
      Result = Data.define(:business_date, :error)

      def self.call(hotel:, business_date:, actor:)
        new(hotel: hotel, business_date: business_date, actor: actor).call
      end

      def initialize(hotel:, business_date:, actor:)
        @hotel = hotel
        @business_date = business_date.to_date
        @actor = actor
      end

      def call
        current = @hotel.current_business_date_record ||
          HotelBusinessDate.initialize_for_hotel!(hotel: @hotel, date: @business_date)

        unless current.business_date == @business_date
          return Result.new(
            business_date: nil,
            error: "Business date #{@business_date} is not the current accounting business date #{current.business_date}."
          )
        end

        return Result.new(business_date: nil, error: "Night audit is already running for this date.") if current.audit_running?

        transitioned = if current.audit_blocked?
          BusinessDates::RetryAudit.call!(hotel: @hotel, actor: @actor, system_context: true)
        else
          BusinessDates::StartAudit.call!(hotel: @hotel, actor: @actor, system_context: true)
        end

        Result.new(business_date: transitioned, error: nil)
      rescue HotelBusinessDate::InvalidTransition => e
        Result.new(business_date: nil, error: e.message)
      end
    end
  end
end
