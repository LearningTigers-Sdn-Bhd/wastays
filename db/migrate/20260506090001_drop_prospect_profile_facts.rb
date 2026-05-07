class DropProspectProfileFacts < ActiveRecord::Migration[8.0]
  def change
    drop_table :prospect_profile_facts do |t|
      t.references :prospect, null: false, foreign_key: true
      t.string :category, null: false
      t.jsonb :facts, null: false, default: {}
      t.datetime :last_seen_at
      t.timestamps

      t.index [ :prospect_id, :category ], unique: true
    end
  end
end
