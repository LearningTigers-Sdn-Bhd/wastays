# frozen_string_literal: true

module NightAudits
  class RepairCompletedNightlyCharges
    MANAGE_PERMISSION = Financials::RepairCompletedNightlyCharges::MANAGE_PERMISSION
    OVERRIDE_PERMISSION = Financials::RepairCompletedNightlyCharges::OVERRIDE_PERMISSION
    POSTING_SOURCE = Financials::RepairCompletedNightlyCharges::POSTING_SOURCE
    Result = Financials::RepairCompletedNightlyCharges::Result

    def self.call(night_audit:, booking:, actor:, reason:)
      Financials::RepairCompletedNightlyCharges.call(
        night_audit: night_audit,
        booking: booking,
        actor: actor,
        reason: reason
      )
    end

    def initialize(night_audit:, booking:, actor:, reason:)
      @implementation = Financials::RepairCompletedNightlyCharges.new(
        night_audit: night_audit,
        booking: booking,
        actor: actor,
        reason: reason
      )
    end

    delegate :call, to: :@implementation
  end
end
