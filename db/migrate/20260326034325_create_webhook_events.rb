class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.string :gateway
      t.string :external_id
      t.jsonb :payload
      t.string :status
      t.text :error_message
      t.datetime :processed_at

      t.timestamps
    end
  end
end
