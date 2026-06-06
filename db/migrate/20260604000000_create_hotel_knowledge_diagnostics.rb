class CreateHotelKnowledgeDiagnostics < ActiveRecord::Migration[8.0]
  def change
    create_table :hotel_knowledge_diagnostics do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :prospect, foreign_key: true
      t.references :prospect_message, foreign_key: true
      t.text :question, null: false
      t.string :intent, null: false
      t.string :topic
      t.string :answer_mode
      t.text :answer
      t.boolean :success, default: false, null: false
      t.string :source
      t.string :diagnostic_status, default: "open", null: false
      t.string :suggested_category
      t.text :routed_categories, default: [], null: false, array: true
      t.text :fallback_categories, default: [], null: false, array: true
      t.jsonb :knowledge_matches, default: [], null: false
      t.integer :match_count, default: 0, null: false
      t.decimal :best_distance, precision: 8, scale: 6
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    add_index :hotel_knowledge_diagnostics, :diagnostic_status
    add_index :hotel_knowledge_diagnostics, :answer_mode
    add_index :hotel_knowledge_diagnostics, :suggested_category
    add_index :hotel_knowledge_diagnostics, :created_at
  end
end
