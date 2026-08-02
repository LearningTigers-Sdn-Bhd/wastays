# frozen_string_literal: true

module NightAudits
  module Resolutions
    class RefreshSnapshot
      def self.call!(night_audit:, business_date_record:, evaluation:)
        night_audit.update!(
          blocked_details: evaluation[:blocked_details],
          exceptions: evaluation[:exceptions],
          summary: night_audit.summary.to_h.merge(evaluation[:summary])
        )

        business_date_record.update!(blockers_snapshot: evaluation[:blocked_details]) unless night_audit.preparing?
      end
    end
  end
end
