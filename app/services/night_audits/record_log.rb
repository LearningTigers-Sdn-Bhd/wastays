# frozen_string_literal: true

module NightAudits
  class RecordLog
    def self.call!(night_audit:, user:, action_type:, message:, metadata: {})
      night_audit.night_audit_logs.create!(
        hotel: night_audit.hotel,
        user: user,
        action_type: action_type,
        message: message,
        metadata: metadata
      )
    end
  end
end
