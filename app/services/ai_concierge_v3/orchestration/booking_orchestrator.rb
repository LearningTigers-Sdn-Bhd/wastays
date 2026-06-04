module AiConciergeV3
  module Orchestration
    class BookingOrchestrator
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
        handle_resume
      when :booking
        revision_response = handle_booking_revision
        return revision_response if revision_response

        selection_follow_up = resolve_selection_follow_up(
          conversation_state: conversation_state,
          interpretation: interpretation,
          active_branch: active_branch,
          pending_question: pending_question
        )
        return selection_follow_up if direct_payload_response?(selection_follow_up) || domain_response?(selection_follow_up)
        return handle_option_selection(interpretation: selection_follow_up, active_branch: active_branch) if selection_follow_up.dig("slots", "selection_id").present?

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
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_booking_timing, pending_question: "booking_timing")
      when :ask_specific_timing
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_specific_timing, pending_question: "specific_timing", extra_context: { month_label: month_label(active_branch) })
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
        handle_option_selection(conversation_state: conversation_state, active_branch: active_branch)
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
        handle_rate_plan_selection(conversation_state: conversation_state, active_branch: active_branch)
      when :confirmation_yes
        handle_confirmation_yes(conversation_state: conversation_state, active_branch: active_branch)
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
            guest_label: guest_label(active_branch)
          }
        )
      when :search_options
        handle_search_options(conversation_state: conversation_state, active_branch: active_branch)
      else
        fallback_response
      end
    end

    def handle_booking_revision(conversation_state: self.conversation_state, active_branch: self.active_branch)
      case BookingRevisionPolicy.new(
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
      selection_follow_up = resolve_selection_follow_up(
        conversation_state: conversation_state,
        interpretation: interpretation,
        active_branch: branch,
        pending_question: "select_option"
      )

      return selection_follow_up if direct_payload_response?(selection_follow_up) || domain_response?(selection_follow_up)
      return handle_option_selection(interpretation: selection_follow_up, active_branch: branch) if selection_follow_up.dig("slots", "selection_id").present?

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

    def handle_resume
      slots_payload, resumed = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).resume_booking
      branch = resumed&.dig("branch") || empty_branch
      resumed_state = temporary_state(conversation_state, slots_payload)

      revision_response = handle_booking_revision(conversation_state: resumed_state, active_branch: branch)
      return revision_response if revision_response

      if resumed&.dig("pending_question") == "confirm_selection" && interpretation["intent"] == "confirmation"
        if interpretation.dig("slots", "confirmation") == "no"
          branch["confirmation_candidate"] = nil
          return booking_response(
            conversation_state: resumed_state,
            active_branch: branch,
            reply_type: :suggest_options,
            pending_question: "select_option",
            extra_context: {
              options: branch["suggested_options"],
              month_label: month_label(branch),
              guest_label: guest_label(branch)
            }
          )
        end

        return handle_confirmation_yes(conversation_state: resumed_state, active_branch: branch)
      end

      if slot_collection_resume?(resumed)
        return process_booking_action(booking_action, conversation_state: resumed_state, active_branch: active_branch)
      end

      if selection_like_resume_message?(interpretation, branch)
        resolved_interpretation = resolve_selection_follow_up(
          conversation_state: resumed_state,
          interpretation: interpretation,
          active_branch: branch,
          pending_question: "select_option"
        )
        return resolved_interpretation if direct_payload_response?(resolved_interpretation)
        return resolved_interpretation if domain_response?(resolved_interpretation)

        resume_slots = if resolved_interpretation.dig("slots", "selection_id").present?
          { "selection_id" => resolved_interpretation.dig("slots", "selection_id") }
        else
          resolved_interpretation["slots"]
        end

        branch = State::SlotMerger.new(
          active_branch: branch,
          slots: resume_slots,
          pending_question: resumed&.dig("pending_question"),
          message: message
        ).call
        return handle_option_selection(conversation_state: resumed_state, interpretation: resolved_interpretation, active_branch: branch)
      end

      if branch["suggested_options"].present?
        search_params = search_params_for(branch)
        return domain_response(
          slots_payload: slots_payload,
          reply_type: :resume_options,
          active_topic: "booking_search",
          active_flow: "booking_search",
          pending_question: "select_option",
          action_name: "request_quote",
          extra_context: {
            options: branch["suggested_options"],
            month_label: month_label(branch),
            guest_label: guest_label(branch),
            search_params: search_params
          }
        )
      end

      return handle_search_options(conversation_state: resumed_state, active_branch: branch) if resumed

      domain_response(slots_payload: conversation_state.slots_payload, reply_type: :ask_booking_timing)
    end

    def booking_action
      if pending_question == "party_split"
        return :search_options unless missing_party_split?
        return :ask_party_split if interpretation["intent"] == "confirmation"
      end

      return :rate_plan_selection if pending_question == "rate_plan_selection"
      return :confirmation_yes if confirmation_yes?
      return :confirmation_no if confirmation_no?
      return :option_selection if interpretation["intent"] == "option_selection"
      return :ask_booking_timing if missing_timing?
      return :ask_specific_timing if missing_specific_timing?
      return :ask_duration if missing_duration?
      return :ask_adult_count if missing_adult_count?
      return :ask_guest_count if missing_guest_count?
      return :ask_party_split if missing_party_split?

      :search_options
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

    def handle_option_selection(conversation_state: self.conversation_state, interpretation: self.interpretation, active_branch: self.active_branch)
      result = tool_registry.fetch("select_booking_option").new(
        option_number: interpretation.dig("slots", "option_number"),
        suggested_options: active_branch["suggested_options"],
        suggestion_set_version: active_branch["suggestion_set_version"],
        selection_id: interpretation.dig("slots", "selection_id"),
        check_in: interpretation.dig("slots", "check_in"),
        message: message,
        pending_selection: active_branch["pending_selection"]
      ).call

      if result["success"]
        selected_option = result["selected_option"]
        rate_plans = Array(selected_option["rate_plans"])

        if rate_plans.size > 1
          active_branch["selected_option"] = selected_option
          active_branch["pending_selection"] = nil
          return booking_response(
            conversation_state: conversation_state,
            active_branch: active_branch,
            reply_type: :ask_rate_plan,
            pending_question: "rate_plan_selection",
            extra_context: { selected_option: selected_option, rate_plans: rate_plans }
          )
        end

        selected_option["selected_rate_plan"] = rate_plans.first if rate_plans.any?
        active_branch["confirmation_candidate"] = selected_option
        active_branch["selected_option"] = selected_option
        active_branch["pending_selection"] = nil
        return booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_confirmation,
          pending_question: "confirm_selection",
          extra_context: { selected_option: result["selected_option"] }
        )
      end

      active_branch["pending_selection"] = pending_selection_for(result)
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: selection_error_reply_type(result) || :invalid_selection,
        pending_question: "select_option",
        extra_context: selection_error_context(result, active_branch)
      )
    end

    def handle_confirmation_yes(conversation_state: self.conversation_state, active_branch: self.active_branch)
      selected_option = active_branch["confirmation_candidate"] || active_branch["selected_option"]
      return booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :invalid_selection, pending_question: "select_option") unless selected_option

      selected_rate_plan = selected_option&.dig("selected_rate_plan") || {}
      result = tool_registry.fetch("generate_booking_url").new(
        hotel: hotel,
        selected_option: selected_option,
        guest_phone: phone || prospect.phone_number,
        rate_plan_id: selected_rate_plan["rate_plan_id"]
      ).call
      return { direct_payload: MessageBuilders::FallbackBuilder.new(message: result["error"]).call } unless result["success"]

      active_branch["selected_option"] = selected_option
      active_branch["confirmation_candidate"] = nil
      payload = booking_payload(conversation_state, active_branch, pending_question: nil, status: "completed")
      payload = State::ConversationTaskManager.new(slots_payload: payload).archive_completed_booking

      domain_response(
        slots_payload: payload,
        reply_type: :booking_link_ready,
        active_topic: nil,
        active_flow: nil,
        pending_question: nil,
        action_name: nil,
        extra_context: { result: result.merge("selected_option" => selected_option) },
        flow_status: "ended",
        end_reason: "booking_url_generated"
      )
    end

    def handle_rate_plan_selection(conversation_state: self.conversation_state, active_branch: self.active_branch)
      rate_plan_name = interpretation.dig("slots", "rate_plan_name")
      selected_option = active_branch["selected_option"]
      rate_plans = Array(selected_option&.dig("rate_plans"))
      matched = Matching::RatePlanMatcher.new(message: message, rate_plan_name: rate_plan_name, rate_plans: rate_plans).call

      if matched
        active_branch["selected_rate_plan_id"] = matched["rate_plan_id"]
        active_branch["selected_rate_plan_name"] = matched["name"]
        selected_option["selected_rate_plan"] = matched
        active_branch["confirmation_candidate"] = selected_option
        active_branch["pending_selection"] = nil
        return booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_confirmation,
          pending_question: "confirm_selection",
          extra_context: { selected_option: selected_option }
        )
      end

      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :ask_rate_plan,
        pending_question: "rate_plan_selection",
        extra_context: { selected_option: selected_option, rate_plans: rate_plans }
      )
    end

    def resolve_selection_follow_up(conversation_state:, interpretation:, active_branch:, pending_question:)
      return interpretation if interpretation.dig("conversation_signals", "end_conversation")
      return interpretation unless pending_question == "select_option"
      return interpretation unless Array(active_branch&.dig("suggested_options")).present?
      return interpretation if informational_intent?(interpretation["intent"])

      branch = active_branch.deep_dup
      result = tool_registry.fetch("select_booking_option").new(
        option_number: interpretation.dig("slots", "option_number"),
        suggested_options: branch["suggested_options"],
        suggestion_set_version: branch["suggestion_set_version"],
        check_in: interpretation.dig("slots", "check_in"),
        message: message,
        pending_selection: branch["pending_selection"]
      ).call

      return resolved_selection_interpretation(interpretation, result) if result["success"]
      return interpretation unless selection_error_reply_type(result)

      branch["pending_selection"] = pending_selection_for(result)
      booking_response(
        conversation_state: conversation_state,
        active_branch: branch,
        reply_type: selection_error_reply_type(result),
        pending_question: "select_option",
        extra_context: selection_error_context(result, branch)
      )
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

    def search_params_for(branch, options: branch["suggested_options"])
      search_params = branch.slice("check_in", "check_out", "adults", "children", "room_count")
      if search_params["check_in"].blank? && Array(options).present?
        first_opt = options.first["options"].first
        search_params["check_in"] = first_opt["check_in"]
        search_params["check_out"] = first_opt["check_out"]
      end
      search_params
    end

    def selection_error_reply_type(result)
      case result["error"]
      when "room_type_requires_option_number"
        :room_type_requires_option_number
      when "ambiguous_option_selection"
        :ambiguous_option_selection
      when "ambiguous_date_selection"
        :ambiguous_date_selection
      end
    end

    def selection_error_context(result, branch)
      case result["error"]
      when "room_type_requires_option_number"
        { room_type_name: result["room_type_name"], room_options: room_options_for(branch, result["room_type_name"]) }
      when "ambiguous_option_selection"
        { room_type_names: result["room_type_names"], option_number: result["option_number"] }
      when "ambiguous_date_selection"
        { room_type_names: result["room_type_names"], check_in: result["check_in"] }
      else
        {}
      end
    end

    def pending_selection_for(result)
      case result["error"]
      when "room_type_requires_option_number"
        { "room_type_name" => result["room_type_name"], "check_in" => result["check_in"] }.compact
      when "ambiguous_date_selection"
        { "check_in" => result["check_in"], "candidate_room_type_names" => result["room_type_names"] }
      else
        nil
      end
    end

    def resolved_selection_interpretation(interpretation, result)
      interpretation.deep_dup.tap do |value|
        value["intent"] = "option_selection"
        value["slots"] = value.fetch("slots", {}).merge("selection_id" => result.dig("selected_option", "selection_id"))
      end
    end

    def room_options_for(branch, room_type_name)
      Array(branch["suggested_options"]).find { |group| group.is_a?(Hash) && group["room_type_name"] == room_type_name }
    end

    def selection_like_resume_message?(interpretation, active_branch)
      return true if interpretation["intent"] == "option_selection"
      return true if interpretation.dig("slots", "check_in").present?
      return true if interpretation.dig("slots", "option_number").present?

      room_type_names = Array(active_branch["suggested_options"]).filter_map { |group| group["room_type_name"] if group.is_a?(Hash) }
      normalized_message = message.downcase.gsub(/[^a-z0-9]+/, " ").squish

      room_type_names.any? do |name|
        name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish.split.any? do |token|
          token.length > 2 && normalized_message.include?(token)
        end
      end
    end

    def slot_collection_resume?(resumed)
      %w[booking_timing specific_timing duration guest_count party_split rate_plan_selection].include?(resumed&.dig("pending_question"))
    end

    def informational_intent?(intent)
      %w[hotel_policy hotel_information nearby_attractions room_information booking_context].include?(intent.to_s)
    end

    def direct_payload_response?(value)
      value.is_a?(Hash) && value.key?(:direct_payload)
    end

    def domain_response?(value)
      value.is_a?(Hash) && value.key?(:slots_payload) && value.key?(:reply_type)
    end

    def empty_branch
      State::SlotMerger.empty_branch
    end

    def pending_question
      decision[:pending_question].presence || State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).booking_pending_question || conversation_state.pending_question
    end

    def confirmation_yes?
      return false unless pending_question == "confirm_selection"

      interpretation["intent"] == "confirmation" && interpretation.dig("slots", "confirmation") != "no"
    end

    def confirmation_no?
      return false unless pending_question == "confirm_selection"

      interpretation["intent"] == "confirmation" && interpretation.dig("slots", "confirmation") == "no"
    end

    def missing_timing?
      active_branch["check_in"].blank? && active_branch["target_month"].blank?
    end

    def missing_specific_timing?
      active_branch["target_month"].present? &&
        active_branch["check_in"].blank? &&
        active_branch["month_segment"].blank?
    end

    def missing_duration?
      has_timing? && duration_missing?
    end

    def has_timing?
      active_branch["check_in"].present? || active_branch["target_month"].present?
    end

    def duration_missing?
      active_branch["check_out"].blank? &&
        active_branch["nights"].to_i <= 0 &&
        active_branch["days"].to_i <= 0
    end

    def missing_adult_count?
      active_branch["children"].to_i.positive? && active_branch["adults"].to_i <= 0
    end

    def missing_guest_count?
      active_branch["party_size_total"].to_i <= 0 &&
        active_branch["adults"].to_i <= 0 &&
        active_branch["children"].to_i <= 0
    end

    def missing_party_split?
      total = active_branch["party_size_total"].to_i
      return false if total <= 0

      adults = active_branch["adults"].to_i
      children = active_branch["children"].to_i

      (adults + children) != total
    end
    end
  end
end
