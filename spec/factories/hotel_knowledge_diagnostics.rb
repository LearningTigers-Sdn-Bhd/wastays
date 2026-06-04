# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_knowledge_diagnostic do
    association :hotel
    question { "Do you provide airport pickup?" }
    intent { "hotel_information" }
    topic { "general_hotel_info" }
    routed_categories { [ "general_info" ] }
    fallback_categories { [ "general_info", "faq", "policy" ] }
    answer_mode { "unavailable" }
    answer { "The hotel has not provided that information yet." }
    success { false }
    source { "general_hotel_info" }
    knowledge_matches { [] }
    match_count { 0 }
    best_distance { nil }
    diagnostic_status { "open" }
    suggested_category { "general_info" }
    metadata { { "producer" => "ai_concierge" } }
  end
end
