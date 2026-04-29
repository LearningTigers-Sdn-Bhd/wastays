class CreateWebhookEndpoints < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_endpoints do |t|
      t.string :name
      t.string :url
      t.boolean :enabled

      t.timestamps
    end
  end
end
