# frozen_string_literal: true

module NightAudits
  module Execution
    class ProcessBookings
      Result = Data.define(:no_shows, :due_outs)

      def self.call(night_audit:, user:)
        Result.new(
          no_shows: NightAudits::ProcessNoShowDetections.call(night_audit: night_audit, user: user),
          due_outs: NightAudits::DetectDueOuts.call(night_audit: night_audit, user: user)
        )
      end
    end
  end
end
