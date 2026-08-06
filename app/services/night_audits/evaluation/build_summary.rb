module NightAudits
  module Evaluation
    class BuildSummary
      def initialize(context:)
        @context = context
      end

      def call
        {
          "arrivals_count" => bookings.checking_in_on(date, zone).count,
          "no_show_detected_count" => bookings.where(status: "no_show_detected").count,
          "no_show_count" => bookings.no_show.checking_in_on(date, zone).count,
          "due_out_count" => bookings.checking_out_on(date, zone).count,
          "checked_out_count" => bookings.completed.where(checked_out_at: hotel.business_day_window_for(date)).count,
          "in_house_count" => bookings.checked_in.intersecting_local_date(date, zone).count,
          "payment_status_counts" => payment_status_counts
        }
      end

      private

      def bookings
        @context.hotel_bookings
      end

      def hotel
        @context.hotel
      end

      def date
        @context.business_date
      end

      def zone
        hotel.hotel_time_zone
      end

      def payment_status_counts
        @context.financially_relevant_bookings
          .group_by(&:payment_status)
          .transform_values(&:count)
          .transform_keys(&:to_s)
      end
    end
  end
end
