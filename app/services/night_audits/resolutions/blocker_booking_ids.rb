# frozen_string_literal: true

module NightAudits
  module Resolutions
    class BlockerBookingIds
      def self.call(night_audit:, business_date_record:, blocker_type:, fresh_blocked_details:)
        sources = [
          night_audit.blocked_details,
          business_date_record&.blockers_snapshot,
          fresh_blocked_details
        ]

        sources.flat_map { |details| ids_from(details, blocker_type) }.uniq
      end

      def self.ids_from(details, blocker_type)
        Array(details.to_h[blocker_type]).filter_map do |item|
          item["booking_id"] || item[:booking_id]
        end.map(&:to_i)
      end

      private_class_method :ids_from
    end
  end
end
