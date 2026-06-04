module AiConciergeV3
  module Orchestration
    class TurnOrchestrator
    END_CONVERSATION_MESSAGE = "No problem, please let me know if you need anything.".freeze
    MAX_TURNS = 50

    def initialize(hotel:, message:, phone: nil, prospect_public_id: nil)
      @hotel = hotel
      @message = message.to_s.strip
      @phone = phone.to_s.strip.presence
      @prospect_public_id = prospect_public_id.to_s.strip.presence
      @tool_registry = Tools::ToolRegistry.new
    end

    def call
      prospect = resolve_prospect
      conversation_state = load_conversation_state(prospect)

      ActiveRecord::Base.transaction do
        reactivate_state!(conversation_state)
        record_inbound_message(prospect)
      end

      if max_turns_exceeded?(conversation_state)
        return Result.success(payload: turn_limit_reached_response(prospect, conversation_state))
      end

      interpretation = Agents::InterpreterAgent.new(
        hotel: hotel,
        message: message,
        conversation_summary: State::ConversationSummaryBuilder.new(conversation_state: conversation_state).call
      ).call
      validate_interpretation!(interpretation)
      conversation_control = ConversationControlPolicy.new(message: message, conversation_state: conversation_state, interpretation: interpretation)

      if conversation_control.cancel_attempt?
        return Result.success(payload: handle_cancel_booking_attempt(prospect:, conversation_state:, interpretation: interpretation))
      end

      if end_confirmation_pending?(conversation_state)
        return handle_end_confirmation_response(prospect:, conversation_state:, interpretation: interpretation, conversation_control: conversation_control)
      end

      if conversation_control.explicit_end?
        if conversation_control.end_confirmation_mode == :generic
          return Result.success(payload: handle_end_conversation(prospect:, conversation_state:, interpretation: interpretation))
        else
          return Result.success(payload: request_end_confirmation(prospect:, conversation_state:, interpretation: interpretation))
        end
      end

      interpretation["conversation_signals"]["end_conversation"] = false
      interpretation = InformationIntentGuard.new(message: message, interpretation: interpretation).call
      booking_context = prepare_booking_context(conversation_state, interpretation)
      conversation_state = booking_context[:conversation_state]
      task_manager = booking_context[:task_manager]
      base_branch = booking_context[:base_branch]
      current_pending_question = booking_context[:pending_question]

      slots = BookingInputNormalizer.new(
        message: message,
        slots: interpretation["slots"],
        pending_question: current_pending_question,
        conversation_signals: interpretation["conversation_signals"],
        active_branch: base_branch
      ).call

      active_branch = State::SlotMerger.new(
        active_branch: base_branch,
        slots: slots,
        pending_question: current_pending_question,
        message: message
      ).call

      decision = TransitionPolicy.new(
        interpretation: interpretation,
        active_branch: active_branch,
        pending_question: current_pending_question,
        message: message,
        booking_task: task_manager.booking_task
      ).call

      response = process_decision(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        active_branch: active_branch,
        decision: decision
      )

      Result.success(payload: response)
    rescue AiConciergeV3::ProspectNotFoundError => e
      Result.failure(error: e.message, status: :not_found)
    rescue ActiveRecord::StaleObjectError
      Result.failure(error: "This conversation was updated by another request. Please try again.", status: :conflict)
    rescue StandardError => e
      Rails.logger.error("AiConciergeV3::TurnOrchestrator error: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      Result.failure(error: "AI Concierge is temporarily unavailable.", status: :internal_server_error)
    end

    private

    attr_reader :hotel, :message, :phone, :prospect_public_id, :tool_registry

    def resolve_prospect
      return resolve_prospect_by_phone if phone.present?

      prospect = hotel.prospects.find_by(public_id: prospect_public_id)
      raise AiConciergeV3::ProspectNotFoundError, "Prospect not found" unless prospect

      prospect
    end

    def resolve_prospect_by_phone
      guest = PhoneIdentity.find_guest(phone)
      existing = hotel.prospects.lookup_by_phone(phone).first
      return existing if existing

      canonical_phone = PhoneIdentity.canonical(phone)
      raise AiConciergeV3::ProspectNotFoundError, "Invalid phone number format" if canonical_phone.blank?

      hotel.prospects.create!(
        phone_number: canonical_phone,
        guest: guest,
        name: guest&.name
      )
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

    def record_inbound_message(prospect)
      prospect&.prospect_messages&.create!(direction: "inbound", body: message)
      prospect&.touch_last_contact!
    end

    def record_outbound_message(prospect, body)
      prospect&.prospect_messages&.create!(direction: "outbound", body: body)
      prospect&.touch_last_contact!
    end

    def validate_interpretation!(interpretation)
      return if Schemas::InterpretationSchema.new.valid?(interpretation)

      raise ArgumentError, "invalid interpretation payload"
    end

    def process_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
      case decision[:action]
      when :greeting
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: :greeting, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil)
      when :confirm_to_end_conversation
        request_end_confirmation(prospect:, conversation_state:, interpretation: interpretation)
      when :end_conversation
        handle_end_conversation(prospect:, conversation_state:, interpretation:)
      when :reset
        payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).reset_tasks
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :reset, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil)
      when :resume, :booking
        handle_booking_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
      when :librarian
        handle_librarian_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
      when :booking_context
        handle_booking_context(prospect:, conversation_state:, interpretation:)
      else
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: nil, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: { message: MessageBuilders::FallbackBuilder::DEFAULT_MESSAGE })
      end
    end

    def handle_booking_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
      domain_result = BookingOrchestrator.new(
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

      return public_direct_payload(domain_result[:direct_payload], prospect) if domain_result.is_a?(Hash) && domain_result.key?(:direct_payload)

      build_and_persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
    end

    def handle_librarian_decision(prospect:, conversation_state:, interpretation:, active_branch:, decision:)
      domain_result = LibrarianOrchestrator.new(
        hotel: hotel,
        message: message,
        interpretation: interpretation,
        conversation_state: conversation_state,
        pause: decision[:pause],
        active_branch: active_branch,
        tool_registry: tool_registry
      ).call

      build_and_persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
    end

    def temporary_state(conversation_state, slots_payload)
      conversation_state.tap do |state|
        state.assign_attributes(slots_payload: slots_payload)
      end
    end

    def prepare_booking_context(conversation_state, interpretation)
      task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)

      if task_manager.booking_pending_question.blank? && conversation_state.pending_question.present?
        normalized_payload = task_manager.activate_booking(task_manager.booking_branch, pending_question: conversation_state.pending_question)
        conversation_state = temporary_state(conversation_state, normalized_payload)
        task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
      end

      pending_question = task_manager.booking_pending_question || conversation_state.pending_question
      base_branch = task_manager.booking_branch

      if interpretation.dig("conversation_signals", "starts_new_booking_branch")
        conversation_state = temporary_state(conversation_state, task_manager.archive_completed_booking)
        task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
        pending_question = nil
        base_branch = empty_branch
      elsif fresh_booking_request_without_details?(interpretation, pending_question)
        conversation_state = temporary_state(conversation_state, task_manager.reset_booking_task)
        task_manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
        pending_question = nil
        base_branch = empty_branch
      end

      {
        conversation_state: conversation_state,
        task_manager: task_manager,
        base_branch: base_branch,
        pending_question: pending_question
      }
    end

    def handle_booking_context(prospect:, conversation_state:, interpretation:)
      result = tool_registry.fetch("get_booking_context").new(hotel: hotel, phone: phone || prospect.phone_number).call
      build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: :booking_context, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: result.symbolize_keys)
    end

    def request_end_confirmation(prospect:, conversation_state:, interpretation:)
      mode = ConversationControlPolicy.new(message: message, conversation_state: conversation_state, interpretation: interpretation).end_confirmation_mode
      build_and_persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
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

    def handle_cancel_booking_attempt(prospect:, conversation_state:, interpretation:)
      slots_payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).reset_booking_task
      build_and_persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        slots_payload: slots_payload,
        reply_type: :booking_attempt_cancelled_next_step,
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil,
        flow_status: "active"
      )
    end

    def handle_end_confirmation_response(prospect:, conversation_state:, interpretation:, conversation_control:)
      if conversation_control.end_confirmation_yes? || conversation_control.explicit_end?
        Result.success(payload: handle_end_conversation(prospect:, conversation_state:, interpretation:))
      else
        Result.success(payload: build_and_persist_response(
          prospect: prospect,
          conversation_state: conversation_state,
          interpretation: interpretation,
          slots_payload: conversation_state.slots_payload,
          reply_type: :end_conversation_declined,
          active_topic: conversation_state.active_topic,
          active_flow: conversation_state.active_flow,
          pending_question: nil,
          action_name: nil,
          flow_status: "active",
        ))
      end
    end

    def handle_end_conversation(prospect:, conversation_state:, interpretation:)
      slots_payload = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).archive_completed_booking
      persist_state(
        conversation_state,
        slots_payload: slots_payload,
        interpretation: interpretation,
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil,
        flow_status: "ended",
        end_reason: "user_ended"
      )
      record_outbound_message(prospect, END_CONVERSATION_MESSAGE)
      ResponsePayloadBuilder.new(reply_message: END_CONVERSATION_MESSAGE, needs_human_support: false, action_name: nil, prospect_public_id: prospect.public_id).call
    end

    def build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload:, reply_type:, active_topic:, active_flow:, pending_question:, action_name:, extra_context: {}, flow_status: nil, end_reason: nil)
      messenger_context = { reply_type: reply_type }.merge(extra_context)
      reply_message = Agents::MessengerAgent.new(hotel: hotel, context: messenger_context).call.fetch("reply_message")
      ActiveRecord::Base.transaction do
        persist_state(conversation_state, slots_payload:, interpretation:, active_topic:, active_flow:, pending_question:, action_name:, flow_status:, end_reason:)
        record_outbound_message(prospect, reply_message)
      end
      ResponsePayloadBuilder.new(reply_message: reply_message, needs_human_support: false, action_name: action_name, prospect_public_id: prospect.public_id).call
    end

    def build_and_persist_domain_response(prospect:, conversation_state:, interpretation:, domain_result:)
      build_and_persist_response(
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
        end_reason: domain_result[:end_reason]
      )
    end

    def public_direct_payload(payload, prospect)
      payload.merge(prospect_public_id: prospect.public_id)
    end

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

    def lifecycle_payload(slots_payload)
      slots_payload["conversation"].is_a?(Hash) ? slots_payload["conversation"].deep_dup : {}
    end

    def empty_branch
      State::SlotMerger.empty_branch
    end

    def fresh_booking_request_without_details?(interpretation, pending_question)
      return false unless %w[booking_timing specific_timing].include?(pending_question.to_s)
      return false unless interpretation["intent"] == "booking_search"
      return false if booking_detail_slots_present?(interpretation["slots"])

      normalized = message.downcase.gsub(/[^a-z0-9]+/, " ").squish
      normalized.match?(/\b(?:book|booking|reserve|reservation|make booking|new booking|start booking)\b/) &&
        !normalized.match?(/\b(?:this month|next month|today|tomorrow|tonight|early|mid|late|jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|\d)\b/)
    end

    def booking_detail_slots_present?(slots)
      %w[target_month target_year month_segment check_in check_out nights days party_size_total adults children room_count option_number].any? do |key|
        value = slots&.dig(key)
        value.present? && value != 0
      end
    end

    def end_confirmation_pending?(conversation_state)
      conversation_state.pending_question == "confirm_to_end_conversation"
    end

    def max_turns_exceeded?(conversation_state)
      conversation_state.slots_payload.dig("conversation", "turn_count").to_i >= MAX_TURNS
    end

    def turn_limit_reached_response(prospect, conversation_state)
      reply = "I've reached my limit for this conversation. Please contact the hotel directly for further assistance."
      persist_state(
        conversation_state,
        slots_payload: conversation_state.slots_payload,
        interpretation: { "intent" => "end_conversation" },
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil,
        flow_status: "ended",
        end_reason: "max_turns_exceeded"
      )
      record_outbound_message(prospect, reply)
      ResponsePayloadBuilder.new(reply_message: reply, needs_human_support: true, action_name: nil, prospect_public_id: prospect.public_id).call
    end
    end
  end
end
