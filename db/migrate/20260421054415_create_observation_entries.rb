class CreateObservationEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :observation_entries do |t|
      t.string :entry_type
      t.string :request_id
      t.integer :status
      t.float :duration
      t.string :path
      t.jsonb :payload

      t.timestamps
    end
    add_index :observation_entries, :entry_type
    add_index :observation_entries, :request_id
    add_index :observation_entries, :status
  end
end
