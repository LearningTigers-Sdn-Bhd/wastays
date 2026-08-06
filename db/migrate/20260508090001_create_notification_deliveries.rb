class CreateNotificationDeliveries < ActiveRecord::Migration[8.0]
  def change
    create_table :notification_deliveries do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.string :notification_type, null: false
      t.string :channel, null: false
      t.string :trigger_event, null: false
      t.string :status, null: false, default: "pending"
      t.string :idempotency_key, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :sent_at
      t.datetime :failed_at
      t.text :error_message

      t.timestamps
    end

    add_index :notification_deliveries, :idempotency_key, unique: true
  end
end
