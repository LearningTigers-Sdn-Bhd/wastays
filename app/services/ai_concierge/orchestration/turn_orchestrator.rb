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

        run_agent_loop(session)
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

      # The tool-calling loop. Everything above it in `process_session` runs
      # first and still costs nothing: a staff member holding the thread, a turn
      # limit, a guest saying goodbye. Control is settled deterministically here
      # rather than after the model, so those turns no longer buy a round-trip
      # to answer a question a regex already answered.
      def run_agent_loop(session)
        control_response = control_handler.handle(
          prospect: session.prospect,
          conversation_state: session.conversation_state,
          interpretation: Core::ConfirmationReader.new(message: message).as_interpretation
        )
        return control_response if control_response

        outcome = AgentLoop::RunTurn.new(
          hotel: hotel,
          prospect: session.prospect,
          phone: phone,
          conversation_state: session.conversation_state,
          message: message,
          thread_language: @conversation&.reply_language
        ).call

        Core::Result.success(
          payload: response_persister.persist_domain_response(
            prospect: session.prospect,
            conversation_state: outcome.conversation_state,
            domain_result: outcome.domain_result
          )
        )
      end

      def session_loader
        @session_loader ||= Turn::SessionLoader.new(
          hotel: hotel,
          message: message,
          phone: phone,
          prospect_public_id: prospect_public_id,
          channel: channel,
          record_inbound: record_inbound
        )
      end

      def control_handler
        @control_handler ||= Turn::ControlHandler.new(message: message, response_persister: response_persister)
      end

      def response_persister
        @response_persister ||= Turn::ResponsePersister.new(hotel: hotel, conversation: @conversation, message: message)
      end
    end
  end
end
