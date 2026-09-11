# frozen_string_literal: true

class CreateStaffNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :staff_notifications do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :subject, polymorphic: true, null: false
      t.string :notification_type, null: false
      t.string :severity, null: false
      t.string :title, null: false
      t.text :message, null: false
      t.string :action_path
      t.jsonb :metadata, null: false, default: {}
      t.string :deduplication_key, null: false
      t.datetime :read_at
      t.datetime :resolved_at

      t.timestamps
    end

    add_index :staff_notifications, :deduplication_key, unique: true
    add_index :staff_notifications,
      [ :hotel_id, :recipient_id, :created_at ],
      where: "resolved_at IS NULL",
      name: "index_active_staff_notifications_for_recipient"
  end
end
