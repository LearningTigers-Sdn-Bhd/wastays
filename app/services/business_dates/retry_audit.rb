# frozen_string_literal: true

module BusinessDates
  class RetryAudit < BaseTransition
    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def call!
      require_manage_permission!

      with_locked_current do |record|
        verify_current!(record)
        require_status!(record, "audit_blocked")
        record.update!(
          status: "audit_running",
          audit_started_at: Time.current,
          blockers_snapshot: {},
          blocked_at: nil
        )
        record
      end
    end
  end
end
