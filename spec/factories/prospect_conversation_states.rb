FactoryBot.define do
  factory :prospect_conversation_state do
    association :prospect
    active_topic { nil }
    active_flow { nil }
    flow_status { "active" }
    pending_question { nil }
    slots_payload { {} }
    last_intent { nil }
    last_action_name { nil }
    last_user_message_at { nil }
    last_topic_switch_at { nil }
    reset_count { 0 }

    # Mid-booking states are built *through* ConversationTaskManager rather than
    # by hand-writing the jsonb, so a change to the payload shape moves these
    # with it instead of leaving specs asserting against a payload the app
    # stopped producing. Every spec that needed one of these used to assemble
    # it inline; there were several spellings of the same state.
    transient do
      booking_branch do
        {
          "target_month" => 8,
          "target_year" => Date.current.month > 8 ? Date.current.year + 1 : Date.current.year,
          "month_segment" => "early",
          "days" => 3,
          "nights" => 2,
          "adults" => 2,
          "children" => 0
        }
      end
      suggested_options { [] }
      selected_option { nil }
    end

    trait :fresh do
      slots_payload { {} }
    end

    trait :awaiting_guest_count do
      active_flow { "booking_search" }
      active_topic { "booking_search" }
      pending_question { "guest_count" }
      slots_payload do
        AiConcierge::State::ConversationTaskManager
          .new(slots_payload: {})
          .activate_booking(booking_branch.except("adults", "children"), pending_question: "guest_count")
      end
    end

    trait :awaiting_option_selection do
      active_flow { "booking_search" }
      active_topic { "booking_search" }
      pending_question { "select_option" }
      slots_payload do
        AiConcierge::State::ConversationTaskManager
          .new(slots_payload: {})
          .activate_booking(
            booking_branch.merge("suggested_options" => suggested_options),
            pending_question: "select_option"
          )
      end
    end

    trait :awaiting_confirmation do
      active_flow { "booking_search" }
      active_topic { "booking_search" }
      pending_question { "confirm_selection" }
      slots_payload do
        AiConcierge::State::ConversationTaskManager
          .new(slots_payload: {})
          .activate_booking(
            booking_branch.merge(
              "suggested_options" => suggested_options,
              "selected_option" => selected_option,
              "confirmation_candidate" => selected_option
            ),
            pending_question: "confirm_selection"
          )
      end
    end

    trait :awaiting_rate_plan do
      active_flow { "booking_search" }
      active_topic { "booking_search" }
      pending_question { "rate_plan_selection" }
      slots_payload do
        AiConcierge::State::ConversationTaskManager
          .new(slots_payload: {})
          .activate_booking(
            booking_branch.merge("selected_option" => selected_option),
            pending_question: "rate_plan_selection"
          )
      end
    end

    # A booking put down mid-flow because the guest asked something else. What
    # makes it resumable is that the branch is in Postgres, not in a context
    # window -- which is the invariant the rewrite must not break.
    trait :suspended_for_information do
      active_flow { "hotel_information" }
      pending_question { "select_option" }
      slots_payload do
        activated = AiConcierge::State::ConversationTaskManager
          .new(slots_payload: {})
          .activate_booking(
            booking_branch.merge("suggested_options" => suggested_options),
            pending_question: "select_option"
          )

        AiConcierge::State::ConversationTaskManager
          .new(slots_payload: activated)
          .suspend_booking_for_information(
            intent: "hotel_information",
            topic: "general_hotel_info",
            pending_question: "select_option"
          )
      end
    end
  end
end
