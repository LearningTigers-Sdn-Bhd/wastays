module AiConcierge
  module Orchestration
    module Booking
      class Orchestrator
    def initialize(hotel:, prospect:, conversation_state:, interpretation:, active_branch:, decision:, message:, phone: nil, tool_registry: Tools::ToolRegistry.new)
      @hotel = hotel
      @prospect = prospect
      @conversation_state = conversation_state
      @interpretation = interpretation
      @active_branch = active_branch || empty_branch
      @decision = decision
      @message = message.to_s
      @phone = phone.to_s.presence
      @tool_registry = tool_registry
    end

    def call
      case decision[:action]
      when :resume
        resume_handler.call
      when :booking
        revision_response = handle_booking_revision
        return revision_response if revision_response

        selection_follow_up = selection_handler.resolve_follow_up(
          conversation_state: conversation_state,
          interpretation: interpretation,
          active_branch: active_branch,
          pending_question: pending_question
        )
        return selection_follow_up if domain_response?(selection_follow_up)
        return selection_handler.handle_selection(conversation_state: conversation_state, interpretation: selection_follow_up, active_branch: active_branch) if selection_follow_up.dig("slots", "selection_id").present?

        process_booking_action(booking_action)
      else
        process_booking_action(decision[:action])
      end
    end

    private

    attr_reader :hotel, :prospect, :conversation_state, :interpretation, :active_branch, :decision, :message, :phone, :tool_registry

    def process_booking_action(action, conversation_state: self.conversation_state, active_branch: self.active_branch)
      case action
      when :ask_booking_timing
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: booking_timing_reply_type, pending_question: "booking_timing")
      when :ask_specific_timing
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_specific_timing, pending_question: "specific_timing", extra_context: { month_label: month_label(active_branch) })
      when :ask_date_range_month
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_date_range_month,
          pending_question: "date_range_month",
          extra_context: { date_range_label: date_range_label(active_branch) }
        )
      when :ask_duration
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_duration, pending_question: "duration")
      when :ask_adult_count
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_adult_count, pending_question: "guest_count")
      when :ask_guest_count
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_guest_count, pending_question: "guest_count", extra_context: { month_label: month_label(active_branch), check_in: active_branch["check_in"] })
      when :ask_party_split
        active_branch["clarification_needed"] = "party_split"
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_party_split,
          pending_question: "party_split",
          extra_context: {
            party_size_total: active_branch["party_size_total"],
            adults: active_branch["adults"],
            children: active_branch["children"]
          }
        )
      when :option_selection
        selection_handler.handle_selection(conversation_state: conversation_state, interpretation: interpretation, active_branch: active_branch)
      when :ask_rate_plan
        selected_option = active_branch["selected_option"] || active_branch["confirmation_candidate"]
        rate_plans = Array(selected_option&.dig("rate_plans"))
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_rate_plan,
          pending_question: "rate_plan_selection",
          extra_context: { selected_option: selected_option, rate_plans: rate_plans }
        )
      when :rate_plan_selection
        rate_plan_selection_handler.call(conversation_state: conversation_state, interpretation: interpretation, active_branch: active_branch)
      when :confirmation_yes
        completion_handler.call(conversation_state: conversation_state, active_branch: active_branch)
      when :confirmation_no
        active_branch["confirmation_candidate"] = nil
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :suggest_options,
          pending_question: "select_option",
          extra_context: {
            options: active_branch["suggested_options"],
            month_label: month_label(active_branch),
            guest_label: guest_label(active_branch),
            search_params: search_params_for(active_branch)
          }
        )
      when :search_options
        handle_search_options(conversation_state: conversation_state, active_branch: active_branch)
      else
        fallback_response
      end
    end

    def handle_booking_revision(conversation_state: self.conversation_state, active_branch: self.active_branch)
      case Booking::RevisionPolicy.new(
        message: message,
        interpretation: interpretation,
        active_branch: active_branch,
        pending_question: pending_question
      ).call
      when :change_rate
        handle_rate_plan_revision(conversation_state: conversation_state, active_branch: active_branch)
      when :change_option
        handle_option_revision(conversation_state: conversation_state, active_branch: active_branch)
      end
    end

    def handle_rate_plan_revision(conversation_state:, active_branch:)
      branch = active_branch.deep_dup
      selected_option = branch["selected_option"] || branch["confirmation_candidate"]

      return ask_for_option_revision(branch, conversation_state: conversation_state) unless selected_option.present?

      rate_plans = Array(selected_option["rate_plans"])
      if rate_plans.many?
        selected_option = selected_option.except("selected_rate_plan")
        branch["selected_option"] = selected_option
        branch["selected_rate_plan_id"] = nil
        branch["selected_rate_plan_name"] = nil
        branch["confirmation_candidate"] = nil

        return booking_response(
          conversation_state: conversation_state,
          active_branch: branch,
          reply_type: :ask_rate_plan,
          pending_question: "rate_plan_selection",
          extra_context: { selected_option: selected_option, rate_plans: rate_plans }
        )
      end

      selected_option["selected_rate_plan"] ||= rate_plans.first if rate_plans.one?
      branch["selected_option"] = selected_option
      branch["confirmation_candidate"] = selected_option
      branch["selected_rate_plan_id"] = selected_option.dig("selected_rate_plan", "rate_plan_id")
      branch["selected_rate_plan_name"] = selected_option.dig("selected_rate_plan", "name")

      booking_response(
        conversation_state: conversation_state,
        active_branch: branch,
        reply_type: :ask_confirmation,
        pending_question: "confirm_selection",
        extra_context: { selected_option: selected_option }
      )
    end

    def handle_option_revision(conversation_state:, active_branch:)
      branch = clear_selected_booking_option(active_branch.deep_dup)
      selection_follow_up = selection_handler.resolve_follow_up(
        conversation_state: conversation_state,
        interpretation: interpretation,
        active_branch: branch,
        pending_question: "select_option"
      )

      return selection_follow_up if domain_response?(selection_follow_up)
      return selection_handler.handle_selection(conversation_state: conversation_state, interpretation: selection_follow_up, active_branch: branch) if selection_follow_up.dig("slots", "selection_id").present?

      ask_for_option_revision(branch, conversation_state: conversation_state)
    end

    def ask_for_option_revision(branch, conversation_state:)
      booking_response(
        conversation_state: conversation_state,
        active_branch: branch,
        reply_type: :suggest_options,
        pending_question: "select_option",
        extra_context: {
          options: branch["suggested_options"],
          month_label: month_label(branch),
          guest_label: guest_label(branch),
          search_params: search_params_for(branch)
        }
      )
    end

    def clear_selected_booking_option(branch)
      branch["selected_option"] = nil
      branch["selected_rate_plan_id"] = nil
      branch["selected_rate_plan_name"] = nil
      branch["confirmation_candidate"] = nil
      branch["pending_selection"] = nil
      branch
    end

    def booking_action
      ActionResolver.new(
        interpretation: interpretation,
        active_branch: active_branch,
        pending_question: pending_question
      ).call
    end

    def handle_search_options(conversation_state: self.conversation_state, active_branch: self.active_branch)
      options = tool_registry.fetch("search_booking_options").new(
        hotel: hotel,
        target_month: active_branch["target_month"],
        target_year: active_branch["target_year"],
        month_segment: active_branch["month_segment"],
        check_in: active_branch["check_in"],
        check_out: active_branch["check_out"],
        adults: active_branch["adults"],
        children: active_branch["children"],
        room_count: active_branch["room_count"],
        nights: active_branch["nights"]
      ).call

      active_branch["clarification_needed"] = nil
      active_branch["suggested_options"] = options
      active_branch["suggestion_set_version"] = active_branch["suggestion_set_version"].to_i + 1

      pending_question = options.empty? ? "booking_timing" : "select_option"
      payload = booking_payload(conversation_state, active_branch, pending_question: pending_question)

      if options.empty?
        domain_response(
          slots_payload: payload,
          reply_type: :no_options,
          active_topic: "booking_search",
          active_flow: "booking_search",
          pending_question: "booking_timing",
          action_name: "request_quote",
          extra_context: { month_label: month_label(active_branch) }
        )
      else
        domain_response(
          slots_payload: payload,
          reply_type: :suggest_options,
          active_topic: "booking_search",
          active_flow: "booking_search",
          pending_question: "select_option",
          action_name: "request_quote",
          extra_context: {
            options: options,
            month_label: month_label(active_branch),
            guest_label: guest_label(active_branch),
            search_params: search_params_for(active_branch, options: options)
          }
        )
      end
    end

    def booking_response(conversation_state: self.conversation_state, active_branch: self.active_branch, reply_type:, pending_question:, extra_context: {}, status: nil, action_name: "request_quote")
      domain_response(
        slots_payload: booking_payload(conversation_state, active_branch, pending_question: pending_question, status: status),
        reply_type: reply_type,
        active_topic: "booking_search",
        active_flow: "booking_search",
        pending_question: pending_question,
        action_name: action_name,
        extra_context: extra_context
      )
    end

    def domain_response(slots_payload:, reply_type:, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: {}, flow_status: nil, end_reason: nil)
      {
        slots_payload: slots_payload,
        reply_type: reply_type,
        active_topic: active_topic,
        active_flow: active_flow,
        pending_question: pending_question,
        action_name: action_name,
        extra_context: extra_context,
        flow_status: flow_status,
        end_reason: end_reason
      }
    end

    def fallback_response
      domain_response(
        slots_payload: conversation_state.slots_payload,
        reply_type: nil,
        extra_context: { message: MessageBuilders::FallbackBuilder::DEFAULT_MESSAGE }
      )
    end

    def booking_timing_reply_type
      room_rate_question? ? :ask_room_rate_timing : :ask_booking_timing
    end

    def room_rate_question?
      Matching::BookingIntentMatcher.new(message: message).rate_question?
    end

    def booking_payload(conversation_state, active_branch, pending_question:, status: nil)
      State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).activate_booking(active_branch, pending_question: pending_question, status: status)
    end

    def temporary_state(conversation_state, slots_payload)
      conversation_state.tap { |state| state.assign_attributes(slots_payload: slots_payload) }
    end

    def month_label(branch)
      month = branch["target_month"]
      year = branch["target_year"]
      return if month.blank? || year.blank?

      [ branch["month_segment"].presence, Date::MONTHNAMES[month.to_i], year ].compact.join(" ")
    end

    def guest_label(branch)
      adults = branch["adults"].to_i
      children = branch["children"].to_i
      parts = []
      parts << "#{adults} adult#{'s' unless adults == 1}" if adults.positive?
      parts << "#{children} child#{'ren' unless children == 1}" if children.positive?
      parts.join(" and ").presence
    end

    def date_range_label(branch)
      clarification = branch["clarification_needed"]
      return unless clarification.is_a?(Hash)

      start_day = clarification["start_day"]
      end_day = clarification["end_day"]
      [ start_day, end_day ].all?(&:present?) ? "#{start_day}-#{end_day}" : nil
    end

    def search_params_for(branch, options: branch["suggested_options"])
      search_params = branch.slice("check_in", "check_out", "adults", "children", "room_count")
      if search_params["check_in"].blank? && Array(options).present?
        first_opt = options.first["options"].first
        search_params["check_in"] = first_opt["check_in"]
        search_params["check_out"] = first_opt["check_out"]
      end
      search_params
    end

    def domain_response?(value)
      value.is_a?(Hash) && value.key?(:slots_payload) && value.key?(:reply_type)
    end

    def empty_branch
      State::SlotMerger.empty_branch
    end

    def selection_handler
      @selection_handler ||= SelectionHandler.new(tool_registry: tool_registry, message: message)
    end

    def rate_plan_selection_handler
      @rate_plan_selection_handler ||= RatePlanSelectionHandler.new(message: message)
    end

    def completion_handler
      @completion_handler ||= CompletionHandler.new(hotel: hotel, prospect: prospect, phone: phone, tool_registry: tool_registry)
    end

    def resume_handler
      @resume_handler ||= ResumeHandler.new(
        conversation_state: conversation_state,
        interpretation: interpretation,
        active_branch: active_branch,
        message: message,
        selection_handler: selection_handler,
        completion_handler: completion_handler,
        action_resolver: method(:booking_action),
        process_booking_action: method(:process_booking_action),
        handle_booking_revision: method(:handle_booking_revision),
        handle_search_options: method(:handle_search_options),
        domain_response: method(:domain_response)
      )
    end

    def pending_question
      decision[:pending_question].presence || State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).booking_pending_question || conversation_state.pending_question
    end
      end
    end
  end
end
