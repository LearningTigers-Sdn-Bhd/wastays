module AiConcierge
  module Orchestration
    module Turn
      class ControlHandler
        # A goodbye, and said as one. It used to be word for word what a guest
        # who declined to end was told, so the two outcomes of the same
        # question read identically -- and only the flow status, which no guest
        # can see, said which had happened.
        END_CONVERSATION_MESSAGE = "Thank you for chatting with us. Message us any time.".freeze
        TURN_LIMIT_REACHED_MESSAGE = "I've reached my limit for this conversation. Please contact the hotel directly for further assistance.".freeze
        WAIT_TIME_END_MESSAGE = "Thank you for reaching out. Please come back again.".freeze
        WAIT_TIME_END_BOOKING_MESSAGE = "It seems you are no longer making a booking quotation. Thank you for reaching out. Please come back again.".freeze

        def initialize(message:, response_persister:)
          @message = message.to_s
          @response_persister = response_persister
        end

        def max_turns_response(prospect:, conversation_state:)
          payload = response_persister.persist_static_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: conversation_state.slots_payload,
            reply_message: TURN_LIMIT_REACHED_MESSAGE,
            needs_human_support: true,
            action_name: nil,
            active_topic: nil,
            active_flow: nil,
            pending_question: nil,
            flow_status: "ended",
            end_reason: "max_turns_exceeded"
          )
          Core::Result.success(payload: payload)
        end

        def wait_time_end?(conversation_state)
          conversation_control(conversation_state: conversation_state, interpretation: {}).wait_time_end?
        end

        def wait_time_end_response(prospect:, conversation_state:)
          control = conversation_control(conversation_state: conversation_state, interpretation: {})
          slots_payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).reset_booking_task
          reply_message = control.booking_progress? ? WAIT_TIME_END_BOOKING_MESSAGE : WAIT_TIME_END_MESSAGE

          payload = response_persister.persist_static_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: slots_payload,
            reply_message: reply_message,
            needs_human_support: false,
            action_name: nil,
            active_topic: nil,
            active_flow: nil,
            pending_question: nil,
            flow_status: "ended",
            end_reason: "wait_time_end"
          )
          Core::Result.success(payload: payload)
        end

        def handle(prospect:, conversation_state:, interpretation:)
          conversation_control = conversation_control(conversation_state: conversation_state, interpretation: interpretation)

          if conversation_control.cancel_attempt?
            return Core::Result.success(payload: handle_cancel_booking_attempt(prospect:, conversation_state:))
          end

          if end_confirmation_pending?(conversation_state)
            return handle_end_confirmation_response(prospect:, conversation_state:, conversation_control: conversation_control)
          end

          return unless conversation_control.explicit_end?

          if conversation_control.end_confirmation_mode == :generic
            Core::Result.success(payload: handle_end_conversation(prospect:, conversation_state:))
          else
            Core::Result.success(payload: request_end_confirmation(prospect:, conversation_state:, interpretation: interpretation))
          end
        end

        private

        attr_reader :message, :response_persister

        def request_end_confirmation(prospect:, conversation_state:, interpretation:)
          mode = Core::ConversationControlPolicy.new(message: message, conversation_state: conversation_state, interpretation: interpretation).end_confirmation_mode
          response_persister.persist_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: conversation_state.slots_payload,
            reply_type: :confirm_to_end_conversation,
            active_topic: conversation_state.active_topic,
            active_flow: conversation_state.active_flow,
            pending_question: "confirm_to_end_conversation",
            action_name: nil,
            flow_status: "active",
            extra_context: { end_confirmation_mode: mode }
          )
        end

        def handle_cancel_booking_attempt(prospect:, conversation_state:)
          slots_payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).reset_booking_task
          response_persister.persist_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: slots_payload,
            reply_type: :booking_attempt_cancelled_next_step,
            active_topic: nil,
            active_flow: nil,
            pending_question: nil,
            action_name: nil,
            flow_status: "active"
          )
        end

        # Three answers, not two.
        #
        # "No" is read before the goodbye words, because at this question a "no
        # thanks" is a refusal to end rather than another way of leaving.
        #
        # And a message that is neither is not a refusal either: it used to be
        # answered "no problem" and dropped, so a guest who asked something on
        # their way out was never answered. Returning nil hands the turn to the
        # model, which is what would have happened had the question never been
        # asked.
        def handle_end_confirmation_response(prospect:, conversation_state:, conversation_control:)
          return decline_end(prospect:, conversation_state:) if conversation_control.end_confirmation_no?
          return Core::Result.success(payload: handle_end_conversation(prospect:, conversation_state:)) if conversation_control.end_confirmation_yes? || conversation_control.explicit_end?

          nil
        end

        def decline_end(prospect:, conversation_state:)
          Core::Result.success(payload: response_persister.persist_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: conversation_state.slots_payload,
            reply_type: :end_conversation_declined,
            active_topic: conversation_state.active_topic,
            active_flow: conversation_state.active_flow,
            pending_question: nil,
            action_name: nil,
            flow_status: "active",
            extra_context: { end_confirmation_mode: end_confirmation_mode(conversation_state) }
          ))
        end

        def end_confirmation_mode(conversation_state)
          Core::ConversationControlPolicy.new(message: message, conversation_state: conversation_state, interpretation: {}).end_confirmation_mode
        end

        def handle_end_conversation(prospect:, conversation_state:)
          slots_payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).archive_completed_booking
          response_persister.persist_static_response(
            prospect: prospect,
            conversation_state: conversation_state,
            slots_payload: slots_payload,
            reply_message: END_CONVERSATION_MESSAGE,
            needs_human_support: false,
            action_name: nil,
            active_topic: nil,
            active_flow: nil,
            pending_question: nil,
            flow_status: "ended",
            end_reason: "user_ended"
          )
        end

        def end_confirmation_pending?(conversation_state)
          conversation_state.pending_question == "confirm_to_end_conversation"
        end

        def conversation_control(conversation_state:, interpretation:)
          Core::ConversationControlPolicy.new(message: message, conversation_state: conversation_state, interpretation: interpretation)
        end
      end
    end
  end
end
