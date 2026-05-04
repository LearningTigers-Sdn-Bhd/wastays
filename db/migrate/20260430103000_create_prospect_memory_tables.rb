class CreateProspectMemoryTables < ActiveRecord::Migration[8.0]
  def change
    create_table :prospects do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :guest, null: true, foreign_key: true
      t.string :phone_number, null: false
      t.string :name
      t.string :stage, null: false, default: "cold"
      t.datetime :last_contact

      t.timestamps
    end

    add_index :prospects, [ :hotel_id, :phone_number ], unique: true
    add_index :prospects, :stage
    add_index :prospects, :last_contact

    create_table :prospect_profile_facts do |t|
      t.references :prospect, null: false, foreign_key: true
      t.string :category, null: false
      t.string :value, null: false

      t.timestamps
    end

    add_index :prospect_profile_facts, [ :prospect_id, :category ], unique: true

    create_table :prospect_messages do |t|
      t.references :prospect, null: false, foreign_key: true
      t.string :direction, null: false
      t.text :body, null: false
      t.datetime :sent_at

      t.timestamps
    end

    add_index :prospect_messages, [ :prospect_id, :sent_at ]
  end
end
