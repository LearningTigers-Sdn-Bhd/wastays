# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_knowledge_document do
    association :hotel
    title { "Test Knowledge Document" }
    source_type { "text" }
    category { "faq" }
    language { "en" }
    embedding_status { "pending" }
    tags { [] }
    version { 1 }
  end
end
