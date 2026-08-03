# frozen_string_literal: true

module NightAudits
  class RecordLog
    def self.call!(**attributes)
      Logging::RecordLog.call!(**attributes)
    end
  end
end
