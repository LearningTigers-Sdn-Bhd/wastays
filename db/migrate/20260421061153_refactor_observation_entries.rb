class RefactorObservationEntries < ActiveRecord::Migration[8.0]
  def up
    drop_table :observation_entries if table_exists?(:observation_entries)

    create_table :observation_entries, id: :uuid do |t|
      t.string :entry_type, null: false
      t.string :request_id
      t.integer :status
      t.float :duration
      t.string :path
      t.jsonb :payload, default: {}
      t.jsonb :tags, default: []

      t.timestamps
    end

    add_index :observation_entries, :entry_type
    add_index :observation_entries, :request_id
    add_index :observation_entries, :status
    add_index :observation_entries, :tags, using: :gin
    add_index :observation_entries, :created_at
  end

  def down
    drop_table :observation_entries if table_exists?(:observation_entries)

    create_table :observation_entries do |t|
      t.string :entry_type
      t.string :request_id
      t.integer :status
      t.float :duration
      t.string :path
      t.jsonb :payload

      t.timestamps
    end
  end
end
