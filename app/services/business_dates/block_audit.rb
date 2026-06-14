# frozen_string_literal: true

module BusinessDates
  class BlockAudit < BaseTransition
    def self.call!(**kwargs)
      new(**kwargs).call!
    end

    def initialize(hotel:, blockers:, actor: nil, system_context: false)
      super(hotel: hotel, actor: actor, system_context: system_context)
      @blockers = blockers.presence || {}
    end

    def call!
      require_manage_permission!

      with_locked_current do |record|
        verify_current!(record)
        require_status!(record, "audit_running")
        record.update!(
          status: "audit_blocked",
          blocked_at: Time.current,
          blockers_snapshot: @blockers
        )
        record
      end
    end
  end
end
