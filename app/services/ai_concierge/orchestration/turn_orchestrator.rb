module AiConcierge
  module Orchestration
    class TurnOrchestrator
      MAX_TURNS = 50

      def initialize(hotel:, message:, phone: nil, prospect_public_id: nil, channel: nil,
                     record_inbound: true)
        @hotel = hotel
        @message = message.to_s.strip
        @phone = phone.to_s.strip.presence
        @prospect_public_id = prospect_public_id.to_s.strip.presence
        @channel = channel.presence
        @record_inbound = record_inbound
        @tool_registry = Tools::ToolRegistry.new
      end

      def call
        session_loader.with_locked_session do |session|
          process_session(session)
        end
      rescue AiConcierge::ProspectNotFoundError => e
        Core::Result.failure(error: e.message, status: :not_found)
      rescue ActiveRecord::StaleObjectError
        Core::Result.failure(error: "This conversation was updated by another request. Please try again.", status: :conflict)
      rescue StandardError => e
        Rails.logger.error("AiConcierge::TurnOrchestrator error: #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
        Core::Result.failure(error: "AI Concierge is temporarily unavailable.", status: :internal_server_error)
      end

      private

      attr_reader :hotel, :message, :phone, :prospect_public_id, :channel, :record_inbound, :tool_registry

      # The thread is captured before anything else runs because the persisters
      # below are memoised with it, and this is the only way into them -- read
      # it as "the turn now belongs to this conversation", not as bookkeeping
      # that can be moved further down.
      def process_session(session)
        @conversation = session.conversation

        return staff_hold_response(session) if session.conversation.human?

        if control_handler.wait_time_end?(session.conversation_state)
          return control_handler.wait_time_end_response(prospect: session.prospect, conversation_state: session.conversation_state)
        end

        if session_loader.max_turns_exceeded?(session.conversation_state)
          return control_handler.max_turns_response(prospect: session.prospect, conversation_state: session.conversation_state)
        end

        interpretation = interpretation_pipeline.interpret(conversation_state: session.conversation_state)
        control_response = control_handler.handle(
          prospect: session.prospect,
          conversation_state: session.conversation_state,
          interpretation: interpretation
        )
        return control_response if control_response

        prepared_turn = interpretation_pipeline.prepare(
          conversation_state: session.conversation_state,
          interpretation: interpretation
        )
        response = process_decision(
          prospect: session.prospect,
          conversation_state: prepared_turn.conversation_state,
          interpretation: prepared_turn.interpretation,
          active_branch: prepared_turn.active_branch,
          decision: prepared_turn.decision
        )

        Core::Result.success(payload: response)
      end

      # A person is holding this thread, so the assistant has nothing to say.
      #
      # The guest's message is already filed by the session loader above and is
      # on its way to the inbox; what stops here is the answer, before any
      # interpreting, any tool and any state is advanced -- a turn the bot did
      # not take is not a turn.
      #
      # Success rather than an error, because nothing went wrong: the message
      # arrived and a person will answer it. `reply_message` is nil because
      # there is genuinely nothing to send, and a caller that delivers it
      # anyway would put an empty message in front of the guest.
      def staff_hold_response(session)
        Core::Result.success(
          payload: Core::ResponsePayloadBuilder.new(
            reply_message: nil,
            needs_human_support: true,
            action_name: nil,
            prospect_public_id: session.prospect.public_id
          ).call
        )
      end

      def process_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
        case decision[:action]
        when :greeting
          response_persister.persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: :greeting, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil)
        when :confirm_to_end_conversation
          control_handler.request_end_confirmation_response(prospect:, conversation_state:, interpretation:)
        when :end_conversation
          control_handler.end_conversation_response(prospect:, conversation_state:, interpretation:)
        when :reset
          payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).reset_tasks
          response_persister.persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :reset, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil)
        when :resume, :booking
          handle_booking_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
        when :librarian
          handle_librarian_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
        when :booking_context
          handle_booking_context(prospect:, conversation_state:, interpretation:)
        else
          response_persister.persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: nil, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: { message: MessageBuilders::FallbackBuilder::DEFAULT_MESSAGE })
        end
      end

      def handle_booking_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
        domain_result = Booking::Orchestrator.new(
          hotel: hotel,
          prospect: prospect,
          conversation_state: conversation_state,
          interpretation: interpretation,
          active_branch: active_branch,
          decision: decision,
          message: message,
          phone: phone,
          tool_registry: tool_registry
        ).call

        return response_persister.public_direct_payload(domain_result[:direct_payload], prospect) if domain_result.is_a?(Hash) && domain_result.key?(:direct_payload)

        response_persister.persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
      end

      def handle_librarian_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
        domain_result = HotelKnowledge::Orchestrator.new(
          hotel: hotel,
          message: message,
          interpretation: interpretation,
          conversation_state: conversation_state,
          pause: decision[:pause],
          active_branch: active_branch,
          tool_registry: tool_registry
        ).call

        response_persister.persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
      end

      def handle_booking_context(prospect:, conversation_state:, interpretation:)
        domain_result = Conversation::BookingContextHandler.new(
          hotel: hotel,
          phone: phone,
          tool_registry: tool_registry
        ).call(prospect: prospect, conversation_state: conversation_state)
        response_persister.persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
      end

      def session_loader
        @session_loader ||= Conversation::SessionLoader.new(
          hotel: hotel,
          message: message,
          phone: phone,
          prospect_public_id: prospect_public_id,
          channel: channel,
          record_inbound: record_inbound
        )
      end

      def interpretation_pipeline
        @interpretation_pipeline ||= Conversation::InterpretationPipeline.new(hotel: hotel, message: message)
      end

      def control_handler
        @control_handler ||= Conversation::ControlHandler.new(message: message, response_persister: response_persister)
      end

      def response_persister
        @response_persister ||= Conversation::ResponsePersister.new(hotel: hotel, conversation: @conversation)
      end
    end
  end
end
