# frozen_string_literal: true

class AddIvfflatIndexToKnowledgeChunks < ActiveRecord::Migration[8.0]
  def change
    add_index :hotel_knowledge_chunks, :embedding,
      using: :ivfflat,
      opclass: :vector_cosine_ops
  end
end
