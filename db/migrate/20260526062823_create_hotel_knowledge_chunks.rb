# frozen_string_literal: true

class CreateHotelKnowledgeChunks < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_knowledge_chunks do |t|
      t.references :hotel_knowledge_document, null: false, foreign_key: true
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.integer :chunk_index, null: false
      t.integer :token_count
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :hotel_knowledge_chunks, [ :hotel_knowledge_document_id, :chunk_index ],
              unique: true,
              name: "idx_knowledge_chunks_on_document_and_index"
  end
end
