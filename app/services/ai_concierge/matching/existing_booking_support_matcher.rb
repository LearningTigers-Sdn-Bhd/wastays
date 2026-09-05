# frozen_string_literal: true

module AiConcierge
  module Matching
    class ExistingBookingSupportMatcher
      BOOKING_REFERENCE = /\b(?:my|an|existing|current|upcoming)\s+(?:booking|reservation|stay)\b|\bi\s+have\s+(?:a\s+)?(?:booking|reservation)\b|\btempahan saya\b|我的.*(?:预订|預訂)/
      STRONG_BOOKING_REFERENCE = /\b(?:my|existing|current|upcoming)\s+(?:booking|reservation)\b|\btempahan saya\b|我的.*(?:预订|預訂)/
      SUPPORT_ATTRIBUTE_REFERENCE = /\bmy\s+(?:check in|check out|arrival|departure|room|guest details|contact details|payment arrangements)\b/
      PORTAL_RESOURCE_REFERENCE = /\bmy\s+(?:booking details|reservation details|receipt|invoice|e invoice|voucher|booking summary|refund request)\b/
      CHANGE = /\b(?:change|move|reschedule|adjust|update|correct|switch|extend|shorten|upgrade)\b/

      def initialize(message:, existing_context: false)
        @normalized = message.to_s.downcase.gsub(/[^\p{Alnum}]+/, " ").squish
        @existing_context = existing_context
      end

      def request_kind
        return unless booking_reference?
        return staff_request_kind if staff_request_kind
        return :portal_cancellation if cancellation_action?
        return :portal_documents if document_request?
        return :portal_general if portal_request?

        :portal_general if explicit_booking_reference?
      end

      def strong_booking_reference?
        normalized.match?(STRONG_BOOKING_REFERENCE)
      end

      private

      attr_reader :normalized, :existing_context

      def booking_reference?
        existing_context || explicit_booking_reference? || normalized.match?(SUPPORT_ATTRIBUTE_REFERENCE) ||
          normalized.match?(PORTAL_RESOURCE_REFERENCE)
      end
      def explicit_booking_reference? = normalized.match?(BOOKING_REFERENCE)

      def staff_request_kind
        return :unsupported_date_change if normalized.match?(CHANGE) && normalized.match?(/\b(?:date|dates|check in|check out|arrival|departure)\b/)
        return :unsupported_room_change if normalized.match?(CHANGE) && normalized.match?(/\b(?:room|rooms|room type|suite|villa)\b/)
        return :unsupported_guest_change if normalized.match?(CHANGE) && normalized.match?(/\b(?:guest|name|email|phone|contact)\b/)
        return :unsupported_exception if normalized.match?(/\b(?:dispute|chargeback|exception|special approval|override)\b/)
        return :unsupported_exception if normalized.match?(/\b(?:wrong|incorrect)\b/) && normalized.match?(/\b(?:payment|card|billing|charge)\b/)

        :unsupported_payment_change if normalized.match?(CHANGE) && normalized.match?(/\b(?:payment|card|billing|charge)\b/)
      end

      def cancellation_action?
        return false if normalized.match?(/\b(?:policy|policies|terms|refundable)\b/)
        return false if attempt_cancellation? && !explicit_existing_booking_reference?

        normalized.match?(/\b(?:cancel|refund|batalkan|bayaran balik)\b/) || normalized.match?(/(?:取消|退款)/)
      end

      def attempt_cancellation?
        normalized.match?(/\b(?:attempt|quote|quotation|percubaan|sebut harga)\b/) ||
          normalized.match?(/(?:尝试|報價|报价)/)
      end

      def explicit_existing_booking_reference?
        normalized.match?(/\b(?:existing|current|upcoming)\s+(?:booking|reservation|stay)\b/) ||
          normalized.match?(/\bi\s+have\s+(?:a\s+)?(?:booking|reservation)\b/) ||
          normalized.match?(/\btempahan saya\b/) || normalized.match?(/我的.*(?:预订|預訂)/)
      end

      def document_request?
        normalized.match?(/\b(?:receipt|invoice|e invoice|voucher|summary|document|documents)\b/)
      end

      def portal_request?
        normalized.match?(/\b(?:manage|view|show|open|access|details|do not disturb|dnd)\b/)
      end
    end
  end
end
