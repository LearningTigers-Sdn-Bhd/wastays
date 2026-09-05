# frozen_string_literal: true

module Concierge
  class SendBookingMagicLink
    ACTIVE_STATUSES = %w[confirmed no_show_detected checked_in due_out_detected checkout_required].freeze

    def initialize(hotel:, conversation:, confirmation_token:)
      @hotel = hotel
      @conversation = conversation
      @confirmation_token = confirmation_token.to_s
    end

    def call
      conversation.prospect.with_lock do
        state = conversation.prospect.prospect_conversation_state ||
          ProspectConversationState.create_or_find_by!(prospect: conversation.prospect)
        manager = AiConcierge::State::ConversationTaskManager.new(slots_payload: state.slots_payload)
        return ignored unless manager.existing_booking_pending?(conversation_id: conversation.id)

        booking = lookup_booking
        domain_response = booking ? issue_response(manager, booking) : not_found_response(manager)
        payload = persist(state, domain_response)

        AiConcierge::Orchestration::Core::Result.success(payload: payload)
      end
    end

    private

    attr_reader :hotel, :conversation, :confirmation_token

    def lookup_booking
      result = BookingLookup.new(hotel: hotel, confirmation_token: confirmation_token).call
      return unless result.success?
      return unless result.booking.status.in?(ACTIVE_STATUSES)

      result.booking.booking_guests.includes(:guest).load
      result.booking
    end

    def issue_response(manager, booking)
      result = Guests::MagicLinks::Issue.new(guest: booking.primary_guest, source: :concierge).call

      if result.success?
        magic_link_response(manager, :magic_link_sent, result)
      elsif result.error_code == :cooldown
        magic_link_response(manager, :magic_link_cooldown, result)
      else
        unavailable_response(manager)
      end
    end

    def magic_link_response(manager, reply_type, result)
      domain_response(
        slots_payload: manager.record_magic_link_sent,
        reply_type: reply_type,
        extra_context: {
          masked_email: result.masked_email,
          protected_names: [ result.masked_email ].compact
        }
      )
    end

    def unavailable_response(manager)
      domain_response(
        slots_payload: manager.offer_existing_booking_handoff(request_kind: :magic_link_failure),
        reply_type: :magic_link_unavailable,
        active_topic: "existing_booking",
        active_flow: "existing_booking"
      )
    end

    def not_found_response(manager)
      slots = manager.reject_existing_booking_code
      locked = slots.dig("existing_booking_task", "status") == "locked"
      domain_response(
        slots_payload: slots,
        reply_type: locked ? :magic_link_unavailable : :existing_booking_not_found,
        active_topic: "existing_booking",
        active_flow: "existing_booking",
        pending_question: locked ? nil : "confirmation_code"
      )
    end

    def domain_response(**attributes)
      AiConcierge::Orchestration::Core::DomainResponse.new(**attributes)
    end

    def persist(state, domain_response)
      AiConcierge::Orchestration::Turn::ResponsePersister.new(
        hotel: hotel,
        conversation: conversation
      ).persist_domain_response(
        prospect: conversation.prospect,
        conversation_state: state,
        domain_result: domain_response
      )
    end

    def ignored
      AiConcierge::Orchestration::Core::Result.failure(
        error: "The conversation is not waiting for a confirmation code.",
        status: :unprocessable_content
      )
    end
  end
end
