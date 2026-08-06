# frozen_string_literal: true

FactoryBot.define do
  factory :hotel_knowledge_chunk do
    association :document, factory: :hotel_knowledge_document
    content { "Sample chunk content" }
    chunk_index { 0 }
    token_count { 3 }
    metadata { {} }
  end
end
