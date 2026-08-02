# frozen_string_literal: true

module NightAudits
  module Resolutions
    class ValidateContext
      def self.call(night_audit:, booking:, actor:, business_date_record:, blocker_booking_ids:, blocker_name:, permission:, allow_unlisted: false, mode: :blocked_run)
        hotel = night_audit.hotel

        return "You do not have permission to resolve Night Audit blockers." unless allowed_actor?(actor, permission, hotel)
        return "Booking does not belong to this hotel." unless booking.hotel_id == hotel.id
        return "Hotel has no current accounting business date." unless business_date_record
        return "Night audit is not for the current accounting business date." unless business_date_record.business_date == night_audit.business_date.to_date
        state_error = validate_state(night_audit, business_date_record, mode)
        return state_error if state_error
        return if resolved?(allow_unlisted) || ids(blocker_booking_ids).include?(booking.id)

        "Booking is not in the #{blocker_name} blocker list."
      end

      def self.validate_state(night_audit, business_date_record, mode)
        case mode.to_sym
        when :preparation
          return "Night audit is not being prepared." unless night_audit.preparing?
          return "Business date must remain open while preparing Night Audit." unless business_date_record.open?
        when :blocked_run
          return "Night audit is not blocked." unless night_audit.blocked?
          return "Business date must be audit blocked before resolving blockers." unless business_date_record.audit_blocked?
        else
          return "Unknown Night Audit blocker resolution mode."
        end

        nil
      end

      def self.allowed_actor?(actor, permission, hotel)
        return true if actor&.respond_to?(:superadmin?) && actor.superadmin?
        return false unless actor&.respond_to?(:has_permission?)

        actor.has_permission?(permission, hotel: hotel)
      end

      def self.resolved?(allow_unlisted)
        allow_unlisted.respond_to?(:call) ? allow_unlisted.call : allow_unlisted
      end

      def self.ids(blocker_booking_ids)
        blocker_booking_ids.respond_to?(:call) ? blocker_booking_ids.call : blocker_booking_ids
      end

      private_class_method :allowed_actor?, :resolved?, :ids, :validate_state
    end
  end
end
