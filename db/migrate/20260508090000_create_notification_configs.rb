class CreateNotificationConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_configs do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :notification_type, null: false
      t.boolean :enabled, null: false, default: true
      t.jsonb :channels, null: false, default: []
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :notification_configs, [ :hotel_id, :notification_type ], unique: true
  end
end
