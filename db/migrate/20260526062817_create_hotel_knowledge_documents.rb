# frozen_string_literal: true

class CreateHotelKnowledgeDocuments < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_knowledge_documents do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :title, null: false
      t.string :source_type, null: false
      t.string :category, null: false
      t.string :language, null: false, default: "en"
      t.string :embedding_status, null: false, default: "pending"
      t.text :tags, array: true, default: []
      t.integer :version, null: false, default: 1
      t.date :effective_date
      t.text :content
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :hotel_knowledge_documents, [ :hotel_id, :category ]
  end
end
