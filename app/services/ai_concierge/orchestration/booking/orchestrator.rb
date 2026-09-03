module AiConcierge
  module Orchestration
    module Booking
      class Orchestrator
    include Responses

    def initialize(hotel:, prospect:, conversation_state:, interpretation:, active_branch:, decision:, message:, phone: nil)
      @hotel = hotel
      @prospect = prospect
      @conversation_state = conversation_state
      @interpretation = interpretation
      @active_branch = active_branch || State::SlotMerger.empty_branch
      @decision = decision
      @message = message.to_s
      @phone = phone.to_s.presence
    end

    # A question the guest keeps failing to answer.
    #
    # Nothing in the ladder used to notice. A guest who answers the rate
    # question with a plan's name -- the natural way to answer it, and no
    # longer a way in -- got the same list back, and again, and again, until
    # the fifty-turn limit ended the conversation on the hotel's terms.
    #
    # The second ask says out loud that the answer did not land. The third
    # stops pretending the bot can get there and asks for a person, without
    # silencing the bot: `request_human!` leaves the thread answering while it
    # waits, which at 2am is the difference between a slow reply and none.
    REASK_NUDGE = 1
    REASK_HANDOVER = 2

    def call
      apply_booking_purpose
      escalate(resume_framing(resolve))
    end

    private

    # A booking put down and picked up again is one turn, not one mode.
    #
    # It used to be a class of its own, handed five bound methods off this one
    # and the branch out of Postgres -- while the branch the guest's own message
    # had just been merged into sat unread. Five of its six exits answered the
    # turn before last: a changed search was answered out of the list that
    # change had already invalidated, and the stale branch was written back
    # over the guest's own words. The ordinary path already loads a
    # suspended booking, already knows which question was open on it, and
    # already clears the suspension on the way out, so resume is that path with
    # a different opening line.
    def resolve
      case decision[:action]
      when :booking, :resume
        price_response = handle_price_exploration
        return price_response if price_response

        revision_response = handle_booking_revision
        return revision_response if revision_response

        selection_follow_up = selection_handler.resolve_follow_up(
          interpretation: interpretation,
          active_branch: active_branch,
          pending_question: pending_question
        )
        return selection_handler.handle_selection(conversation_state: conversation_state, interpretation: selection_follow_up, active_branch: active_branch) if selection_follow_up.dig("slots", "selection_id").present?

        process_booking_action(booking_action)
      else
        process_booking_action(decision[:action])
      end
    end

    attr_reader :hotel, :prospect, :conversation_state, :interpretation, :active_branch, :decision, :message, :phone

    def apply_booking_purpose
      return if decision[:purpose].blank?

      manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
      @started_in_price_exploration = manager.price_exploration?
      conversation_state.assign_attributes(slots_payload: manager.set_booking_purpose(decision[:purpose]))
    end

    def price_exploration_turn?
      @started_in_price_exploration || State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).price_exploration?
    end

    def resumed? = decision[:action] == :resume

    # Where the guest left off, said as that.
    #
    # A guest coming back from a question of their own is not a guest failing
    # to answer, so the turn re-asks nothing: the count goes back to zero and
    # the nudge `escalate` would otherwise put in front of the reply stays off.
    # And a message that matches no row -- "hello again" -- is not a misread
    # answer to a list they cannot see any more, it is the moment to put the
    # list back in front of them.
    def resume_framing(result)
      return result unless resumed? && domain_response?(result)
      return clear_reask(result) unless result.reply_type == :invalid_selection

      clear_reask(options_response(active_branch: resumed_branch(result), reply_type: :resume_options))
    end

    def clear_reask(result)
      task = result.dig(:slots_payload, "booking_task")
      return result unless task.is_a?(Hash)

      result.with(slots_payload: result.slots_payload.merge("booking_task" => task.merge("reask_count" => 0)))
    end

    # The branch the turn actually ran on, read back off the payload it wrote
    # rather than off `active_branch`, which the handlers below take copies of.
    def resumed_branch(result)
      branch = result.dig(:slots_payload, "booking_task", "branch")
      branch.is_a?(Hash) ? branch : active_branch
    end

    def escalate(result)
      return result unless domain_response?(result)

      reasks = result.dig(:slots_payload, "booking_task", "reask_count").to_i
      return result if reasks < REASK_NUDGE

      nudged = result.with(extra_context: result.extra_context.merge(retry: true))
      return nudged if reasks < REASK_HANDOVER

      nudged.with(
        needs_human_support: true,
        next_action: booking_next_action(
          slots_payload: nudged.slots_payload,
          reply_type: nudged.reply_type,
          pending_question: nudged.pending_question,
          needs_human_support: true
        )
      )
    end

    def process_booking_action(action, conversation_state: self.conversation_state, active_branch: self.active_branch)
      case action
      when :ask_booking_timing
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: booking_timing_reply_type,
          pending_question: "booking_timing",
          extra_context: { how_to_question: how_to_booking_question? }
        )
      when :past_timing
        handle_past_timing(conversation_state: conversation_state, active_branch: active_branch)
      when :ask_specific_timing
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_specific_timing, pending_question: "specific_timing", extra_context: { branch: active_branch })
      when :ask_date_range_month
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_date_range_month,
          pending_question: "date_range_month",
          extra_context: { branch: active_branch }
        )
      when :ask_duration
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_duration, pending_question: "duration")
      when :ask_adult_count
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_adult_count, pending_question: "guest_count")
      when :ask_guest_count
        booking_response(conversation_state: conversation_state, active_branch: active_branch, reply_type: :ask_guest_count, pending_question: "guest_count", extra_context: { branch: active_branch, check_in: active_branch["check_in"] })
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
      when :ask_confirmation
        booking_response(
          conversation_state: conversation_state,
          active_branch: active_branch,
          reply_type: :ask_confirmation,
          pending_question: "confirm_selection",
          extra_context: { selected_option: active_branch["confirmation_candidate"] || active_branch["selected_option"] }
        )
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
        rate_plan_selection_handler.call(conversation_state: conversation_state, active_branch: active_branch) ||
          handle_search_options(conversation_state: conversation_state, active_branch: active_branch)
      when :confirmation_yes
        completion_handler.call(conversation_state: conversation_state, active_branch: active_branch)
      when :confirmation_no
        active_branch["confirmation_candidate"] = nil
        options_response(conversation_state: conversation_state, active_branch: active_branch)
      when :search_options
        handle_search_options(conversation_state: conversation_state, active_branch: active_branch)
      else
        fallback_response
      end
    end

    def handle_price_exploration
      return unless price_exploration_turn?

      result = referenced_price_option
      if result&.fetch("success", false)
        return continue_price_option(result["selected_option"]) if explicit_purchase_requested?

        return show_price_option_details(result["selected_option"])
      end

      return continue_viewed_option if explicit_purchase_requested? && active_branch["viewed_option"].present?
      return if explicit_purchase_requested? && priced_options.blank?
      return price_option_invalid_response if price_option_reference?
      return price_option_required_response if explicit_purchase_requested?
      return price_option_guidance_response if price_progress_word? && active_branch["viewed_option"].present?
      return decline_viewed_option if confirmation_answer == "no" && active_branch["viewed_option"].present?
      return show_price_option_details(active_branch["viewed_option"]) if pending_question == "price_option_continuation" && active_branch["viewed_option"].present?

      nil
    end

    def continue_viewed_option
      option = active_branch["viewed_option"]
      return price_option_required_response if option.blank?

      continue_price_option(option)
    end

    def continue_price_option(option)
      set_booking_purpose("booking")
      selection_handler.continue_with_option(
        conversation_state: conversation_state,
        active_branch: active_branch,
        selected_option: option
      )
    end

    def show_price_option_details(option)
      return price_option_required_response if option.blank?

      details = Tools::RoomInformation::GetRoomTypeDetailsTool.new(
        hotel: hotel,
        query: option["room_type_name"],
        room_type_name: option["room_type_name"]
      ).call
      return refresh_price_options unless details["success"]

      set_booking_purpose("price_exploration")
      active_branch["viewed_option"] = option
      active_branch["selected_option"] = nil
      active_branch["confirmation_candidate"] = nil
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :price_option_details,
        pending_question: "price_option_continuation",
        extra_context: { selected_option: option, room_details: details, branch: active_branch }
      )
    end

    def decline_viewed_option
      set_booking_purpose("price_exploration")
      active_branch["viewed_option"] = nil
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :price_option_declined,
        pending_question: "price_option_exploration"
      )
    end

    def price_option_required_response
      set_booking_purpose("price_exploration")
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :price_option_required,
        pending_question: "price_option_exploration"
      )
    end

    def price_option_guidance_response
      set_booking_purpose("price_exploration")
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :price_option_guidance,
        pending_question: "price_option_continuation"
      )
    end

    def price_option_invalid_response
      set_booking_purpose("price_exploration")
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :price_option_invalid,
        pending_question: "price_option_exploration"
      )
    end

    def refresh_price_options
      set_booking_purpose("price_exploration")
      active_branch["viewed_option"] = nil
      handle_search_options
    end

    def referenced_price_option
      return unless price_option_reference?

      result = Tools::Booking::SelectBookingOptionTool.new(
        option_number: referenced_option_number,
        suggested_options: active_branch["suggested_options"],
        suggestion_set_version: active_branch["suggestion_set_version"],
        message: message
      ).call
      return result unless result["success"]
      return result if result.dig("selected_option", "position").to_i == referenced_option_number.to_i

      { "success" => false, "error" => "invalid_selection" }
    end

    def referenced_option_number
      return cheapest_option&.dig("position") if cheapest_reference?

      Matching::OptionReference.new(message: message).number || interpretation.dig("slots", "option_number")
    end

    def cheapest_option
      Array(active_branch["suggested_options"]).flat_map { |group| Array(group["options"]) }.min_by do |option|
        option["total_price"].to_f
      end
    end

    def price_option_reference?
      Matching::OptionReference.new(message: message).number.present? ||
        interpretation.dig("slots", "option_number").present? ||
        (cheapest_reference? && cheapest_option.present?)
    end

    def cheapest_reference?
      message.downcase.match?(/\b(?:cheapest|lowest)\b/)
    end

    def explicit_purchase_requested?
      booking_intent.explicit_purchase_commitment?
    end

    def price_progress_word?
      confirmation_answer == "yes" || message.downcase.match?(/\b(?:continue|proceed)\b/)
    end

    def confirmation_answer
      interpretation.dig("slots", "confirmation") || Core::ConfirmationReader.new(message: message).confirmation
    end

    def priced_options
      Array(active_branch["suggested_options"])
    end

    def set_booking_purpose(purpose)
      manager = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload)
      conversation_state.assign_attributes(slots_payload: manager.set_booking_purpose(purpose))
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
        interpretation: interpretation,
        active_branch: branch,
        pending_question: "select_option"
      )

      return selection_handler.handle_selection(conversation_state: conversation_state, interpretation: selection_follow_up, active_branch: branch) if selection_follow_up.dig("slots", "selection_id").present?

      ask_for_option_revision(branch, conversation_state: conversation_state)
    end

    def ask_for_option_revision(branch, conversation_state:)
      options_response(conversation_state: conversation_state, active_branch: branch)
    end

    # The catalogue, said the same way every time it is put in front of the
    # guest -- after a search, after a "no", after a change of room, and when
    # a booking is picked back up. Four copies of this used to drift.
    def options_response(active_branch:, conversation_state: self.conversation_state, reply_type: :suggest_options, options: active_branch["suggested_options"])
      price_exploration = State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).price_exploration?
      reply_type = :price_options if price_exploration && reply_type == :suggest_options
      pending = price_exploration ? "price_option_exploration" : "select_option"
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: reply_type,
        pending_question: pending,
        extra_context: {
          options: options,
          branch: active_branch,
          search_params: search_params_for(active_branch),
          flexible_search: active_branch["check_in"].blank?,
          price_exploration: price_exploration
        }
      )
    end

    def clear_selected_booking_option(branch)
      branch["selected_option"] = nil
      branch["selected_rate_plan_id"] = nil
      branch["selected_rate_plan_name"] = nil
      branch["confirmation_candidate"] = nil
      branch
    end

    def booking_action
      ActionResolver.new(
        interpretation: interpretation,
        active_branch: active_branch,
        pending_question: pending_question
      ).call
    end

    # The date is cleared as it is named. Leaving it on the branch would make
    # the ladder say the same thing every turn, and the guest cannot correct a
    # date the hotel keeps holding on to.
    def handle_past_timing(conversation_state:, active_branch:)
      branch = active_branch.deep_dup
      stale_check_in = branch["check_in"]
      %w[check_in check_out target_month target_year month_segment nights days].each { |key| branch.delete(key) }

      booking_response(
        conversation_state: conversation_state,
        active_branch: branch,
        reply_type: :timing_in_the_past,
        pending_question: "booking_timing",
        extra_context: { check_in: stale_check_in }
      )
    end

    def handle_search_options(conversation_state: self.conversation_state, active_branch: self.active_branch)
      options = Tools::Booking::SearchBookingOptionsTool.new(
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

      return options_response(conversation_state: conversation_state, active_branch: active_branch, options: options) if options.any?

      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: :no_options,
        pending_question: "booking_timing",
        extra_context: { branch: active_branch }
      )
    end

    def fallback_response
      Core::DomainResponse.new(
        slots_payload: conversation_state.slots_payload,
        reply_type: nil,
        extra_context: { message: MessageBuilders::DEFAULT_MESSAGE }
      )
    end

    def booking_timing_reply_type
      room_rate_question? ? :ask_room_rate_timing : :ask_booking_timing
    end

    def room_rate_question?
      booking_intent.rate_question?
    end

    def how_to_booking_question?
      booking_intent.how_to_question?
    end

    def booking_intent
      @booking_intent ||= Matching::BookingIntentMatcher.new(message: message)
    end

    def search_params_for(branch)
      branch.slice("check_in", "check_out", "adults", "children", "room_count")
    end

    def domain_response?(value)
      value.is_a?(Core::DomainResponse)
    end

    def selection_handler
      @selection_handler ||= SelectionHandler.new(message: message)
    end

    def rate_plan_selection_handler
      @rate_plan_selection_handler ||= RatePlanSelectionHandler.new(message: message)
    end

    def completion_handler
      @completion_handler ||= CompletionHandler.new(hotel: hotel, prospect: prospect, phone: phone)
    end

    def pending_question
      decision[:pending_question].presence || State::ConversationTaskManager.new(slots_payload: conversation_state.slots_payload).booking_pending_question || conversation_state.pending_question
    end
      end
    end
  end
end
