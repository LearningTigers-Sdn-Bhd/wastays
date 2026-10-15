# frozen_string_literal: true

module AiConcierge
  module Escalation
    class Policy
      TRIGGERS = %w[emergency guest_asks_for_person complaint booking_change payment_question no_answer].freeze

      Result = Data.define(:trigger, :handoff, :message) do
        def handoff? = handoff
      end

      def initialize(hotel:, conversation:, trigger:, failure_count: 0)
        @hotel = hotel
        @conversation = conversation
        @trigger = trigger.to_s.presence_in(TRIGGERS)
        @failure_count = failure_count.to_i
      end

      def call
        return result(false) if trigger.blank?
        return result(false) if conversation&.human_requested? || conversation&.human?

        result(handoff?)
      end

      private

      attr_reader :hotel, :conversation, :trigger, :failure_count

      def handoff?
        return true if trigger.in?(%w[emergency guest_asks_for_person])
        return false unless contact&.escalates_on?(trigger)
        return failure_count >= contact.escalation_attempts if trigger == "no_answer"

        true
      end

      def result(handoff)
        Result.new(
          trigger: trigger,
          handoff: handoff,
          message: handoff ? front_desk_status.support_message(reason: trigger) : nil
        )
      end

      def contact = hotel.guest_contact

      def front_desk_status
        @front_desk_status ||= Concierge::FrontDeskStatusPresenter.new(hotel: hotel)
      end
    end
  end
end
