module AiConcierge
  module Orchestration
    module Turn
      class SessionLoader
        Session = Struct.new(:prospect, :conversation, :conversation_state, keyword_init: true)

        DEFAULT_CHANNEL = "whatsapp"

        # `record_inbound: false` says the caller has already filed the guest's
        # message. The web chat does: it saves what was typed and shows it before
        # handing the answer to a job, so the guest is not left looking at an
        # empty thread while a model thinks. Filing it a second time here would
        # show them their own question twice.
        def initialize(hotel:, message:, phone: nil, prospect_public_id: nil,
                       channel: DEFAULT_CHANNEL, record_inbound: true)
          @hotel = hotel
          @message = message.to_s.strip
          @phone = phone.to_s.strip.presence
          @prospect_public_id = prospect_public_id.to_s.strip.presence
          @channel = channel.presence || DEFAULT_CHANNEL
          @record_inbound = record_inbound
        end

        def with_locked_session
          prospect = resolve_prospect

          prospect.with_lock do
            conversation = resolve_conversation(prospect)
            conversation_state = load_conversation_state(prospect)
            ActiveRecord::Base.transaction do
              reactivate_state!(conversation_state)
              record_inbound_message(prospect, conversation) if record_inbound?
            end

            yield Session.new(prospect: prospect, conversation: conversation, conversation_state: conversation_state)
          end
        end

        def max_turns_exceeded?(conversation_state)
          conversation_state.slots_payload.dig("conversation", "turn_count").to_i >= TurnOrchestrator::MAX_TURNS
        end

        private

        attr_reader :hotel, :message, :phone, :prospect_public_id, :channel

        def record_inbound? = @record_inbound

        def resolve_prospect
          return resolve_prospect_by_phone if phone.present?

          prospect = hotel.prospects.find_by(public_id: prospect_public_id)
          raise AiConcierge::ProspectNotFoundError, "Prospect not found" unless prospect

          prospect
        end

        def resolve_prospect_by_phone
          guest = PhoneIdentity.find_guest(phone)
          existing = hotel.prospects.lookup_by_phone(phone).first
          return existing if existing

          canonical_phone = PhoneIdentity.canonical(phone)
          raise AiConcierge::ProspectNotFoundError, "Invalid phone number format" if canonical_phone.blank?

          hotel.prospects.create!(
            phone_number: canonical_phone,
            guest: guest,
            name: guest&.name
          )
        end

        # A thread the guest is still in gets continued; anything already closed
        # starts a fresh one, so a guest returning months later is not dropped
        # back into the middle of an old exchange. `prospect.with_lock` upstream
        # serialises this, and the partial unique index is the backstop.
        def resolve_conversation(prospect)
          prospect.conversations.open.find_by(channel: channel) ||
            prospect.conversations.create!(hotel: prospect.hotel, channel: channel)
        end

        def load_conversation_state(prospect)
          prospect.prospect_conversation_state || ProspectConversationState.create_or_find_by!(prospect: prospect)
        end

        def reactivate_state!(conversation_state)
          return unless conversation_state.flow_status == "ended"

          payload = conversation_state.slots_payload.deep_dup
          conversation = lifecycle_payload(payload)
          conversation["status"] = "active"
          conversation["ended_at"] = nil
          conversation["end_reason"] = nil
          payload["conversation"] = conversation

          conversation_state.update!(flow_status: "active", slots_payload: payload)
        end

        def record_inbound_message(prospect, conversation)
          prospect&.prospect_messages&.create!(
            conversation: conversation,
            direction: "inbound",
            sender_role: "guest",
            body: message
          )
          prospect&.touch_last_contact!
        end

        def lifecycle_payload(slots_payload)
          slots_payload["conversation"].is_a?(Hash) ? slots_payload["conversation"].deep_dup : {}
        end
      end
    end
  end
end
