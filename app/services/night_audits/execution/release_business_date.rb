# frozen_string_literal: true

module NightAudits
  module Execution
    class ReleaseBusinessDate
      def self.call!(hotel:, business_date:)
        HotelBusinessDate.transaction do
          record = hotel.hotel_business_dates.current.lock.first
          unless record&.business_date == business_date.to_date && record.audit_running?
            raise HotelBusinessDate::InvalidTransition, "Night Audit can only release its current running business date."
          end

          record.update!(
            status: "open",
            audit_started_at: nil,
            blocked_at: nil,
            blockers_snapshot: {}
          )
          record
        end
      end
    end
  end
end
