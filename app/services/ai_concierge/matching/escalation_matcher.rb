# frozen_string_literal: true

module AiConcierge
  module Matching
    class EscalationMatcher
      PERSON = /\b(?:speak|talk|connect|transfer|message|contact)\b.*\b(?:person|human|staff|team|front desk|manager)\b|\b(?:ask|want|need)\b.*\b(?:a person|a human|human agent|staff member|team member|manager)\b|\b(?:real person|human agent)\b|\b(?:human|staff|manager|front desk)\s+(?:please|now)\b|(?:真人|人工客服|前台人员)|\b(?:orang sebenar|kakitangan|meja depan)\b/i
      EMERGENCY = /\b(?:emergency|ambulance|medical emergency|call the police|building is on fire|room is on fire|there(?:'s| is) a fire|cannot breathe|can't breathe|not breathing|unconscious)\b|(?:紧急|救护车|火灾|报警)|\b(?:kecemasan|ambulans|kebakaran|polis)\b/i

      def initialize(message:)
        @message = message.to_s
      end

      def call
        return "emergency" if message.match?(EMERGENCY)

        "guest_asks_for_person" if message.match?(PERSON)
      end

      private

      attr_reader :message
    end
  end
end
