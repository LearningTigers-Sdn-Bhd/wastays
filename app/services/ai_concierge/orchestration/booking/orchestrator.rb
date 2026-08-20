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
      reasks >= REASK_HANDOVER ? nudged.with(needs_human_support: true) : nudged
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
      booking_response(
        conversation_state: conversation_state,
        active_branch: active_branch,
        reply_type: reply_type,
        pending_question: "select_option",
        extra_context: {
          options: options,
          month_label: month_label(active_branch),
          guest_label: guest_label(active_branch),
          search_params: search_params_for(active_branch, options: options)
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
        extra_context: { month_label: month_label(active_branch) }
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
