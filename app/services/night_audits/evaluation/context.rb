module NightAudits
  module Evaluation
    class Context
      PHASES = %i[pre_close post_close].freeze

      attr_reader :hotel, :business_date, :phase

      def initialize(hotel:, business_date:, phase:)
        @hotel = hotel
        @business_date = business_date.to_date
        @phase = phase.to_sym if phase.respond_to?(:to_sym)

        raise ArgumentError, "unknown night audit evaluation phase: #{phase.inspect}" unless PHASES.include?(@phase)
      end

      def hotel_bookings
        @hotel_bookings ||= hotel.bookings
      end

      def financially_relevant_bookings
        @financially_relevant_bookings ||= FinanciallyRelevantBookings.call(
          hotel: hotel,
          business_date: business_date
        ).to_a
      end

      def nightly_charge_candidates
        @nightly_charge_candidates ||= NightlyChargeCandidates.call(
          hotel: hotel,
          business_date: business_date
        ).to_a
      end

      def pre_close?
        phase == :pre_close
      end

      def post_close?
        phase == :post_close
      end
    end
  end
end
