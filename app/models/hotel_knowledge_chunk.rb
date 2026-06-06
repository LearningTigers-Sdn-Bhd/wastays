# frozen_string_literal: true

class HotelKnowledgeChunk < ApplicationRecord
  belongs_to :document, class_name: "HotelKnowledgeDocument", foreign_key: :hotel_knowledge_document_id

  has_neighbors :embedding
end
