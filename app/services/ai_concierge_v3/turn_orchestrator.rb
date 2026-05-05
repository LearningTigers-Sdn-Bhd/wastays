module AiConciergeV3
  class TurnOrchestrator
    def initialize(hotel:, message:, phone:, identity_mode:)
      @hotel = hotel
      @message = message.to_s.strip
      @phone = phone.to_s.strip.presence
      @identity_mode = identity_mode
      @tool_registry = ToolRegistry.new
    end

    def call
      prospect = resolve_prospect
      conversation_state = load_conversation_state(prospect)
      record_inbound_message(prospect)

      interpretation = InterpreterAgent.new(
        hotel: hotel,
        message: message,
        conversation_summary: ConversationSummaryBuilder.new(conversation_state: conversation_state).call
      ).call
      validate_interpretation!(interpretation)

      if interpretation.dig("conversation_signals", "starts_new_booking_branch")
        new_payload = BranchManager.new(slots_payload: conversation_state.slots_payload).archive_completed_active
        conversation_state = temporary_state(conversation_state, new_payload)
        base_branch = empty_branch
      else
        base_branch = conversation_state.slots_payload["active"]
      end

      interpretation = resolve_selection_follow_up(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        active_branch: base_branch,
        pending_question: conversation_state.pending_question
      )
      return Result.success(payload: interpretation) if interpretation.is_a?(Hash) && interpretation.key?(:reply_message)

      slots = filtered_slots_for_merge(
        slots: interpretation["slots"],
        pending_question: conversation_state.pending_question,
        conversation_signals: interpretation["conversation_signals"]
      )

      active_branch = SlotMerger.new(
        active_branch: base_branch,
        slots: slots,
        pending_question: conversation_state.pending_question,
        message: message
      ).call

      decision = TransitionPolicy.new(
        interpretation: interpretation,
        active_branch: active_branch,
        paused_flows: conversation_state&.paused_flows,
        pending_question: conversation_state&.pending_question,
        message: message
      ).call

      response = process_decision(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        active_branch: active_branch,
        decision: decision
      )

      Result.success(payload: response)
    rescue StandardError => e
      Rails.logger.error("AiConciergeV3::TurnOrchestrator error: #{e.class}: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n")) if e.backtrace
      Result.success(payload: MessageBuilders::FallbackBuilder.new.call)
    end

    private

    attr_reader :hotel, :message, :phone, :identity_mode, :tool_registry

    def resolve_prospect
      return unless identity_mode == :known_contact && phone.present?

      guest = PhoneIdentity.find_guest(phone)
      hotel.prospects.lookup_by_phone(phone).first || hotel.prospects.create!(
        phone_number: PhoneIdentity.canonical(phone),
        guest: guest,
        name: guest&.name
      )
    end

    def load_conversation_state(prospect)
      return NullConversationState.new unless prospect

      prospect.prospect_conversation_state || prospect.create_prospect_conversation_state!
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
      when :reset
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: { "paused_flows" => [], "completed_booking_branches" => [] }, reply_type: :reset, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil)
      when :resume
        handle_resume(prospect:, conversation_state:, interpretation:)
      when :hotel_policy
        handle_hotel_policy(prospect:, conversation_state:, interpretation:, active_branch:, pause: decision[:pause])
      when :hotel_information
        handle_hotel_information(prospect:, conversation_state:, interpretation:, active_branch:, pause: decision[:pause])
      when :nearby_attractions
        handle_nearby_attractions(prospect:, conversation_state:, interpretation:, active_branch:, pause: decision[:pause])
      when :room_information
        handle_room_information(prospect:, conversation_state:, interpretation:, active_branch:, pause: decision[:pause])
      when :booking_context
        handle_booking_context(prospect:, conversation_state:, interpretation:)
      when :ask_booking_timing
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ask_booking_timing, active_topic: "booking_search", active_flow: "booking_search", pending_question: "booking_timing", action_name: "request_quote")
      when :ask_duration
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ask_duration, active_topic: "booking_search", active_flow: "booking_search", pending_question: "duration", action_name: "request_quote")
      when :ask_adult_count
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ask_adult_count, active_topic: "booking_search", active_flow: "booking_search", pending_question: "guest_count", action_name: "request_quote")
      when :ask_guest_count
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ask_guest_count, active_topic: "booking_search", active_flow: "booking_search", pending_question: "guest_count", action_name: "request_quote", extra_context: { month_label: month_label(active_branch) })
      when :ask_party_split
        active_branch["clarification_needed"] = "party_split"
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ask_party_split, active_topic: "booking_search", active_flow: "booking_search", pending_question: "party_split", action_name: "request_quote", extra_context: { party_size_total: active_branch["party_size_total"] })
      when :option_selection
        handle_option_selection(prospect:, conversation_state:, interpretation:, active_branch:)
      when :confirmation_yes
        handle_confirmation_yes(prospect:, conversation_state:, interpretation:, active_branch:)
      when :confirmation_no
        active_branch["confirmation_candidate"] = nil
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :decline_confirmation, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote")
      when :search_options
        handle_search_options(prospect:, conversation_state:, interpretation:, active_branch:)
      else
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: nil, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: { message: MessageBuilders::FallbackBuilder::DEFAULT_MESSAGE })
      end
    end

    def handle_resume(prospect:, conversation_state:, interpretation:)
      slots_payload, resumed = BranchManager.new(slots_payload: conversation_state.slots_payload).resume_latest
      active_branch = slots_payload["active"] || empty_branch
      resumed_state = temporary_state(conversation_state, slots_payload)

      if selection_like_resume_message?(interpretation, active_branch)
        resolved_interpretation = resolve_selection_follow_up(
          prospect: prospect,
          conversation_state: resumed_state,
          interpretation: interpretation,
          active_branch: active_branch,
          pending_question: "select_option"
        )
        return resolved_interpretation if resolved_interpretation.is_a?(Hash) && resolved_interpretation.key?(:reply_message)

        resume_slots = if resolved_interpretation.dig("slots", "selection_id").present?
          { "selection_id" => resolved_interpretation.dig("slots", "selection_id") }
        else
          resolved_interpretation["slots"]
        end

        active_branch = SlotMerger.new(
          active_branch: active_branch,
          slots: resume_slots,
          pending_question: conversation_state&.pending_question,
          message: message
        ).call
        return handle_option_selection(prospect:, conversation_state: resumed_state, interpretation: resolved_interpretation, active_branch:)
      end

      if active_branch["suggested_options"].present?
        reply = MessengerAgent.new(hotel: hotel, context: {
          reply_type: :resume_options,
          options: active_branch["suggested_options"],
          month_label: month_label(active_branch),
          guest_label: guest_label(active_branch)
        }).call.fetch("reply_message")

        persist_state(conversation_state, slots_payload:, interpretation:, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote")
        record_outbound_message(prospect, reply)
        return ResponsePayloadBuilder.new(reply_message: reply, needs_human_support: false, action_name: "request_quote").call
      end

      return handle_search_options(prospect:, conversation_state:, interpretation:, active_branch:) if resumed

      build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: :ask_booking_timing, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil)
    end

    def temporary_state(conversation_state, slots_payload)
      return conversation_state if conversation_state.is_a?(NullConversationState)

      conversation_state.tap do |state|
        state.assign_attributes(slots_payload: slots_payload)
      end
    end

    def handle_hotel_policy(prospect:, conversation_state:, interpretation:, active_branch:, pause:)
      slots_payload = info_slots_payload(conversation_state:, active_branch:, pause:)
      result = tool_registry.fetch("get_hotel_policy").new(hotel: hotel, policy_topic: interpretation["topic"]).call

      build_and_persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        slots_payload: slots_payload,
        reply_type: :hotel_policy,
        active_topic: pause ? "hotel_policy" : nil,
        active_flow: pause ? "hotel_policy" : nil,
        pending_question: nil,
        action_name: nil,
        extra_context: { result: result }
      )
    end

    def handle_hotel_information(prospect:, conversation_state:, interpretation:, active_branch:, pause:)
      slots_payload = info_slots_payload(conversation_state:, active_branch:, pause:)
      tool_name, reply_type = hotel_information_tool_and_reply_type_for(interpretation)
      result = tool_registry.fetch(tool_name).new(hotel: hotel).call

      build_and_persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        slots_payload: slots_payload,
        reply_type: reply_type,
        active_topic: pause ? interpretation["topic"] : nil,
        active_flow: pause ? "hotel_information" : nil,
        pending_question: nil,
        action_name: nil,
        extra_context: { result: result }
      )
    end

    def handle_nearby_attractions(prospect:, conversation_state:, interpretation:, active_branch:, pause:)
      slots_payload = info_slots_payload(conversation_state:, active_branch:, pause:)
      result = tool_registry.fetch("get_nearby_attractions").new(hotel: hotel).call

      build_and_persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        slots_payload: slots_payload,
        reply_type: :nearby_attractions,
        active_topic: pause ? "nearby_attractions" : nil,
        active_flow: pause ? "hotel_information" : nil,
        pending_question: nil,
        action_name: nil,
        extra_context: { result: result }
      )
    end

    def handle_room_information(prospect:, conversation_state:, interpretation:, active_branch:, pause:)
      slots_payload = info_slots_payload(conversation_state:, active_branch:, pause:)
      tool_name = interpretation["topic"] == "room_type_faq" ? "get_room_type_faq" : "get_room_type_details"
      result = tool_registry.fetch(tool_name).new(
        hotel: hotel,
        query: message,
        room_type_name: interpretation.dig("slots", "room_type_name")
      ).call

      reply_type = if result["success"]
        interpretation["topic"] == "room_type_faq" ? :room_type_faq : :room_type_details
      elsif result["error"] == "ambiguous_room_type"
        :ambiguous_room_type
      else
        :room_type_not_found
      end

      build_and_persist_response(
        prospect: prospect,
        conversation_state: conversation_state,
        interpretation: interpretation,
        slots_payload: slots_payload,
        reply_type: reply_type,
        active_topic: pause ? interpretation["topic"] : nil,
        active_flow: pause ? "room_information" : nil,
        pending_question: nil,
        action_name: nil,
        extra_context: { result: result }
      )
    end

    def handle_booking_context(prospect:, conversation_state:, interpretation:)
      result = tool_registry.fetch("get_booking_context").new(hotel: hotel, phone: phone).call
      build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: :booking_context, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: result.symbolize_keys)
    end

    def handle_search_options(prospect:, conversation_state:, interpretation:, active_branch:)
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

      payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
      if options.empty?
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :no_options, active_topic: "booking_search", active_flow: "booking_search", pending_question: "booking_timing", action_name: "request_quote", extra_context: { month_label: month_label(active_branch) })
      else
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :suggest_options, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { options: options, month_label: month_label(active_branch), guest_label: guest_label(active_branch) })
      end
    end

    def handle_option_selection(prospect:, conversation_state:, interpretation:, active_branch:)
      result = tool_registry.fetch("select_booking_option").new(
        option_number: interpretation.dig("slots", "option_number"),
        suggested_options: active_branch["suggested_options"],
        suggestion_set_version: active_branch["suggestion_set_version"],
        selection_id: interpretation.dig("slots", "selection_id"),
        check_in: interpretation.dig("slots", "check_in"),
        message: message,
        pending_selection: active_branch["pending_selection"]
      ).call

      payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
      if result["success"]
        active_branch["confirmation_candidate"] = result["selected_option"]
        active_branch["selected_option"] = result["selected_option"]
        active_branch["pending_selection"] = nil
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ask_confirmation, active_topic: "booking_search", active_flow: "booking_search", pending_question: "confirm_selection", action_name: "request_quote", extra_context: { selected_option: result["selected_option"] })
      elsif result["error"] == "room_type_requires_option_number"
        active_branch["pending_selection"] = {
          "room_type_name" => result["room_type_name"],
          "check_in" => result["check_in"]
        }.compact
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :room_type_requires_option_number, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { room_type_name: result["room_type_name"], room_options: room_options_for(active_branch, result["room_type_name"]) })
      elsif result["error"] == "ambiguous_option_selection"
        active_branch["pending_selection"] = nil
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ambiguous_option_selection, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { room_type_names: result["room_type_names"], option_number: result["option_number"] })
      elsif result["error"] == "ambiguous_date_selection"
        active_branch["pending_selection"] = {
          "check_in" => result["check_in"],
          "candidate_room_type_names" => result["room_type_names"]
        }
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ambiguous_date_selection, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { room_type_names: result["room_type_names"], check_in: result["check_in"] })
      else
        active_branch["pending_selection"] = nil
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :invalid_selection, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote")
      end
    end

    def handle_confirmation_yes(prospect:, conversation_state:, interpretation:, active_branch:)
      selected_option = active_branch["confirmation_candidate"] || active_branch["selected_option"]
      return build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: conversation_state.slots_payload, reply_type: :invalid_selection, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote") unless selected_option

      result = tool_registry.fetch("generate_booking_url").new(hotel: hotel, selected_option: selected_option, guest_phone: phone).call
      return Result.success(payload: MessageBuilders::FallbackBuilder.new(message: result["error"]).call).payload unless result["success"]

      active_branch["selected_option"] = selected_option
      active_branch["confirmation_candidate"] = nil
      payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(active_branch)
      payload = BranchManager.new(slots_payload: payload).archive_completed_active

      build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :booking_link_ready, active_topic: nil, active_flow: nil, pending_question: nil, action_name: nil, extra_context: { result: result.merge("selected_option" => selected_option) })
    end

    def build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload:, reply_type:, active_topic:, active_flow:, pending_question:, action_name:, extra_context: {})
      messenger_context = { reply_type: reply_type }.merge(extra_context)
      reply_message = MessengerAgent.new(hotel: hotel, context: messenger_context).call.fetch("reply_message")
      persist_state(conversation_state, slots_payload:, interpretation:, active_topic:, active_flow:, pending_question:, action_name:)
      record_outbound_message(prospect, reply_message)
      ResponsePayloadBuilder.new(reply_message: reply_message, needs_human_support: false, action_name: action_name).call
    end

    def persist_state(conversation_state, slots_payload:, interpretation:, active_topic:, active_flow:, pending_question:, action_name:)
      return if conversation_state.is_a?(NullConversationState)

      patch = StatePatchBuilder.new(
        conversation_state: conversation_state,
        slots_payload: slots_payload,
        active_topic: active_topic,
        active_flow: active_flow,
        pending_question: pending_question,
        last_intent: interpretation["intent"],
        last_action_name: action_name,
        flow_status: active_flow.present? ? "active" : "completed",
        now: Time.current
      ).call
      conversation_state.update!(patch)
    end

    def month_label(branch)
      month = branch["target_month"]
      year = branch["target_year"]
      return if month.blank? || year.blank?

      prefix = branch["month_segment"].presence
      [ prefix, Date::MONTHNAMES[month.to_i], year ].compact.join(" ")
    end

    def guest_label(branch)
      adults = branch["adults"].to_i
      children = branch["children"].to_i
      parts = []
      parts << "#{adults} adult#{'s' unless adults == 1}" if adults.positive?
      parts << "#{children} child#{'ren' unless children == 1}" if children.positive?
      parts.join(" and ").presence
    end

    def info_slots_payload(conversation_state:, active_branch:, pause:)
      slots_payload = conversation_state.slots_payload
      slots_payload = BranchManager.new(slots_payload: slots_payload).start_branch(active_branch)
      return slots_payload unless pause

      BranchManager.new(slots_payload: slots_payload).pause_active(topic: "booking_search", pending_question: conversation_state.pending_question || "select_option")
    end

    def hotel_information_tool_and_reply_type_for(interpretation)
      case interpretation["topic"]
      when "hotel_faq"
        ["get_hotel_faq", :hotel_faq]
      else
        ["get_general_hotel_info", :general_hotel_info]
      end
    end

    def filtered_slots_for_merge(slots:, pending_question:, conversation_signals:)
      filtered_slots = slots.is_a?(Hash) ? slots.deep_dup : {}
      return filtered_slots if conversation_signals.to_h["is_correction"]

      timing_keys = %w[target_month target_year month_segment check_in check_out]
      duration_keys = %w[days nights]

      timing_keys.each { |key| filtered_slots.delete(key) } unless explicit_timing_in_message?
      duration_keys.each { |key| filtered_slots.delete(key) } unless explicit_duration_in_message?
      filtered_slots.delete("check_out") unless explicit_checkout_in_message?
      apply_guest_count_guards!(filtered_slots)

      case pending_question
      when "duration", "guest_count", "party_split", "confirm_selection", "select_option"
        timing_keys.each { |key| filtered_slots.delete(key) }
      end

      filtered_slots
    end

    def explicit_timing_in_message?
      normalized = message.downcase

      normalized.match?(/\b(?:early|mid|late)\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\bnext month\b/) ||
        normalized.match?(/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?\b/) ||
        normalized.match?(/\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/) ||
        normalized.match?(/\b\d{4}-\d{2}-\d{2}\b/)
    end

    def explicit_duration_in_message?
      normalized = message.downcase

      normalized.match?(/\b\d+\s*nights?\b/) ||
        normalized.match?(/\b\d+\s*days?\b/) ||
        normalized.match?(/\bstay(?:ing)?\s+for\s+\d+\s*(?:days?|nights?)\b/) ||
        normalized.match?(/\bfor\s+\d+\s*(?:days?|nights?)\b/)
    end

    def explicit_checkout_in_message?
      normalized = message.downcase

      normalized.match?(/\bcheck\s*out\b/) ||
        normalized.match?(/\bfrom\b.*\bto\b/) ||
        normalized.match?(/\buntil\b/) ||
        normalized.match?(/\btill\b/) ||
        normalized.scan(/\b\d{4}-\d{2}-\d{2}\b/).size >= 2 ||
        normalized.scan(/\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}(?:st|nd|rd|th)?\b/).size >= 2 ||
        normalized.scan(/\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b/).size >= 2
    end

    def apply_guest_count_guards!(filtered_slots)
      if explicit_people_total_in_message?
        filtered_slots["party_size_total"] = extracted_people_total if extracted_people_total.positive?
        filtered_slots.delete("adults") unless explicit_adults_in_message?
        filtered_slots.delete("children") unless explicit_children_in_message?
      end

      if explicit_adults_in_message? && !explicit_children_in_message? && extracted_adult_count.positive?
        filtered_slots["adults"] = extracted_adult_count
        filtered_slots.delete("children") unless explicit_people_total_in_message?
      end

      if explicit_children_in_message? && !explicit_adults_in_message? && extracted_children_count.positive?
        filtered_slots["children"] = extracted_children_count
      end
    end

    def explicit_people_total_in_message?
      message.downcase.match?(/\b\d+\s+people\b/)
    end

    def explicit_adults_in_message?
      message.downcase.match?(/\badults?\b/)
    end

    def explicit_children_in_message?
      message.downcase.match?(/\bchildren?\b/)
    end

    def extracted_people_total
      message.downcase[/\b(\d+)\s+people\b/, 1].to_i
    end

    def extracted_adult_count
      message.downcase[/\b(\d+)\s+adults?\b/, 1].to_i
    end

    def extracted_children_count
      message.downcase[/\b(\d+)\s+children?\b/, 1].to_i
    end

    def resolve_selection_follow_up(prospect:, conversation_state:, interpretation:, active_branch:, pending_question:)
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

      case result["error"]
      when "room_type_requires_option_number"
        branch["pending_selection"] = {
          "room_type_name" => result["room_type_name"],
          "check_in" => result["check_in"]
        }.compact
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :room_type_requires_option_number, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { room_type_name: result["room_type_name"], room_options: room_options_for(branch, result["room_type_name"]) })
      when "ambiguous_option_selection"
        branch["pending_selection"] = nil
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ambiguous_option_selection, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { room_type_names: result["room_type_names"], option_number: result["option_number"] })
      when "ambiguous_date_selection"
        branch["pending_selection"] = {
          "check_in" => result["check_in"],
          "candidate_room_type_names" => result["room_type_names"]
        }
        payload = BranchManager.new(slots_payload: conversation_state.slots_payload).start_branch(branch)
        build_and_persist_response(prospect:, conversation_state:, interpretation:, slots_payload: payload, reply_type: :ambiguous_date_selection, active_topic: "booking_search", active_flow: "booking_search", pending_question: "select_option", action_name: "request_quote", extra_context: { room_type_names: result["room_type_names"], check_in: result["check_in"] })
      else
        return interpretation unless result["success"]

        interpretation.deep_dup.tap do |value|
          value["intent"] = "option_selection"
          value["slots"] = value.fetch("slots", {}).merge("selection_id" => result.dig("selected_option", "selection_id"))
        end
      end
    end

    def room_options_for(branch, room_type_name)
      Array(branch["suggested_options"]).find do |group|
        group.is_a?(Hash) && group["room_type_name"] == room_type_name
      end
    end

    def selection_like_resume_message?(interpretation, active_branch)
      return true if interpretation["intent"] == "option_selection"
      return true if interpretation.dig("slots", "check_in").present?
      return true if interpretation.dig("slots", "option_number").present?

      room_type_names = Array(active_branch["suggested_options"]).filter_map do |group|
        group["room_type_name"] if group.is_a?(Hash)
      end
      normalized_message = message.downcase.gsub(/[^a-z0-9]+/, " ").squish

      room_type_names.any? do |name|
        name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squish.split.any? do |token|
          token.length > 2 && normalized_message.include?(token)
        end
      end
    end

    def empty_branch
      SlotMerger.new(active_branch: nil, slots: {}, pending_question: nil, message: nil).send(:default_branch)
    end

    def informational_intent?(intent)
      %w[hotel_policy hotel_information nearby_attractions room_information booking_context].include?(intent.to_s)
    end

    class NullConversationState
      def active_topic
        nil
      end

      def active_flow
        nil
      end

      def flow_status
        "completed"
      end

      def slots_payload
        { "paused_flows" => [], "completed_booking_branches" => [] }
      end

      def paused_flows
        []
      end

      def pending_question
        nil
      end

      def last_user_message_at
        nil
      end
    end
  end
end
