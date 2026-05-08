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
  end
end
