# frozen_string_literal: true

module AiConcierge
  module Orchestration
    module Turn
      class ExistingBookingSupportHandler
        SEND_LINK = /\b(?:send|email)\b.*\b(?:link|login)\b|\b(?:login|magic)\s+link\b/
        ASK_TEAM = /\b(?:ask|contact|speak|talk|message)\b.*\b(?:hotel|team|staff|person|human|front desk)\b/

        def initialize(message:, conversation:)
          @message = message.to_s
          @conversation = conversation
        end

        def call(conversation_state:)
          return unless conversation

          manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
          return whatsapp_cancellation(manager) if whatsapp? && cancellation_request?(manager)
          return unless web?
          return request_code(manager) if portal_offered?(manager) && wants_magic_link?
          return request_staff(manager) if handoff_requested?(manager)
          return if manager.existing_booking_pending?(conversation_id: conversation.id)

          route_new_request(manager)
        end

        private

        attr_reader :message, :conversation

        def route_new_request(manager)
          matcher = Matching::ExistingBookingSupportMatcher.new(
            message: message,
            existing_context: portal_offered?(manager) || handoff_offered?(manager)
          )
          request_kind = matcher.request_kind
          return unless request_kind
          return if active_new_booking?(manager) && request_kind == :unsupported_date_change && !matcher.strong_booking_reference?

          if request_kind.to_s.start_with?("unsupported_")
            handoff_offer(manager, request_kind)
          else
            portal_offer(manager, request_kind)
          end
        end

        def request_code(manager)
          domain_response(
            slots_payload: manager.request_existing_booking_code(conversation_id: conversation.id),
            reply_type: :ask_existing_booking_confirmation_code,
            active_topic: "existing_booking",
            active_flow: "existing_booking",
            pending_question: "confirmation_code"
          )
        end

        def portal_offer(manager, request_kind)
          domain_response(
            slots_payload: manager.offer_existing_booking_portal(
              request_kind: request_kind,
              conversation_id: conversation.id
            ),
            reply_type: request_kind == :portal_cancellation ? :existing_booking_cancellation_portal : :existing_booking_portal,
            active_topic: "existing_booking",
            active_flow: "existing_booking"
          )
        end

        def handoff_offer(manager, request_kind)
          domain_response(
            slots_payload: manager.offer_existing_booking_handoff(
              request_kind: request_kind,
              conversation_id: conversation.id
            ),
            reply_type: request_kind,
            active_topic: "existing_booking",
            active_flow: "existing_booking"
          )
        end

        def request_staff(manager)
          domain_response(
            slots_payload: manager.record_booking_support_requested,
            reply_type: :booking_support_requested,
            needs_human_support: true
          )
        end

        def handoff_requested?(manager)
          (handoff_offered?(manager) || portal_offered?(manager) || link_sent?(manager)) &&
            (message.downcase.match?(ASK_TEAM) || Core::ConfirmationReader.new(message: message).confirmation == "yes")
        end

        def cancellation_request?(manager)
          Matching::ExistingBookingSupportMatcher.new(
            message: message,
            existing_context: portal_offered?(manager) || handoff_offered?(manager) || link_sent?(manager)
          ).request_kind == :portal_cancellation
        end

        def whatsapp_cancellation(manager)
          domain_response(
            slots_payload: manager.record_booking_support_requested,
            reply_type: :booking_cancellation_support_requested,
            needs_human_support: true
          )
        end

        def portal_offered?(manager)
          manager.existing_booking_portal_offered?(conversation_id: conversation.id)
        end

        def handoff_offered?(manager)
          manager.existing_booking_handoff_offered?(conversation_id: conversation.id)
        end

        def link_sent?(manager)
          manager.existing_booking_link_sent?(conversation_id: conversation.id)
        end

        def web? = conversation.channel == Concierge::PostWebMessage::CHANNEL
        def whatsapp? = conversation.channel == "whatsapp"

        def wants_magic_link?
          message.downcase.match?(SEND_LINK) || Core::ConfirmationReader.new(message: message).confirmation == "yes"
        end

        def active_new_booking?(manager)
          !manager.booking_task["status"].in?(%w[idle expired suspended])
        end

        def domain_response(**attributes)
          Core::DomainResponse.new(**attributes)
        end
      end
    end
  end
end
