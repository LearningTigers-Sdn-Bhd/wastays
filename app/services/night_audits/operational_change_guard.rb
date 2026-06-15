# frozen_string_literal: true

module NightAudits
  class OperationalChangeGuard
    class OperationalChangeBlocked < StandardError; end

    ERROR_MESSAGE = "Night Audit is currently running for this business date. Financially relevant booking changes are temporarily locked until the audit completes or becomes blocked.".freeze

    def self.call!(hotel:, action:, night_audit: nil)
      new(hotel: hotel, action: action, night_audit: night_audit).call!
    end

    def initialize(hotel:, action:, night_audit: nil)
      @hotel = hotel
      @action = action
      @night_audit = night_audit
    end

    def call!
      business_date = @hotel.current_business_date_record
      return true unless business_date&.audit_running?
      return true if active_night_audit?(business_date)

      raise OperationalChangeBlocked, ERROR_MESSAGE
    end

    private

    def active_night_audit?(business_date)
      @night_audit.is_a?(NightAudit) &&
        @night_audit.persisted? &&
        @night_audit.running? &&
        @night_audit.hotel_id == @hotel.id &&
        @night_audit.business_date == business_date.business_date
    end
  end
end
