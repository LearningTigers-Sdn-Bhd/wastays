module AiConcierge
  module Orchestration
    module Conversation
      class ResponsePersister
        def initialize(hotel:, conversation: nil)
          @hotel = hotel
          @conversation = conversation
        end

        def persist_response(prospect:, conversation_state:, interpretation:, slots_payload:, reply_type:, active_topic:, active_flow:, pending_question:, action_name:, extra_context: {}, flow_status: nil, end_reason: nil, needs_human_support: false)
          messenger_context = { reply_type: reply_type }.merge(extra_context)
          reply_message = Agents::MessengerAgent.new(hotel: hotel, context: messenger_context).call.fetch("reply_message")
          persist_static_response(
            prospect: prospect,
            conversation_state: conversation_state,
            interpretation: interpretation,
            slots_payload: slots_payload,
            reply_message: reply_message,
            needs_human_support: needs_human_support,
            action_name: action_name,
            active_topic: active_topic,
            active_flow: active_flow,
            pending_question: pending_question,
            flow_status: flow_status,
            end_reason: end_reason
          )
        end

        def persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
          persist_response(
            prospect: prospect,
            conversation_state: conversation_state,
            interpretation: interpretation,
            slots_payload: domain_result.fetch(:slots_payload),
            reply_type: domain_result[:reply_type],
            active_topic: domain_result[:active_topic],
            active_flow: domain_result[:active_flow],
            pending_question: domain_result[:pending_question],
            action_name: domain_result[:action_name],
            extra_context: domain_result[:extra_context] || {},
            flow_status: domain_result[:flow_status],
            end_reason: domain_result[:end_reason],
            needs_human_support: domain_result[:needs_human_support] || false
          )
        end

        def persist_static_response(prospect:, conversation_state:, interpretation:, slots_payload:, reply_message:, needs_human_support:, action_name:, active_topic:, active_flow:, pending_question:, flow_status:, end_reason:)
          ActiveRecord::Base.transaction do
            persist_state(conversation_state, slots_payload:, interpretation:, active_topic:, active_flow:, pending_question:, action_name:, flow_status:, end_reason:)
            record_outbound_message(prospect, reply_message)
          end
          Core::ResponsePayloadBuilder.new(reply_message: reply_message, needs_human_support: needs_human_support, action_name: action_name, prospect_public_id: prospect.public_id).call
        end

        private

        attr_reader :hotel, :conversation

        def persist_state(conversation_state, slots_payload:, interpretation:, active_topic:, active_flow:, pending_question:, action_name:, flow_status: nil, end_reason: nil)
          patch = State::StatePatchBuilder.new(
            conversation_state: conversation_state,
            slots_payload: slots_payload,
            active_topic: active_topic,
            active_flow: active_flow,
            pending_question: pending_question,
            last_intent: interpretation["intent"],
            last_action_name: action_name,
            flow_status: flow_status || (active_flow.present? ? "active" : "completed"),
            end_reason: end_reason,
            now: Time.current
          ).call
          conversation_state.update!(patch)
        end

        # `sender_role` is stated rather than left to the direction default: once
        # staff can reply, "outbound" stops implying the bot wrote it, and a
        # message that guessed its own author would be wrong from that day on.
        def record_outbound_message(prospect, body)
          prospect&.prospect_messages&.create!(
            conversation: conversation,
            direction: "outbound",
            sender_role: "bot",
            body: body
          )
          prospect&.touch_last_contact!
        end
      end
    end
  end
end
