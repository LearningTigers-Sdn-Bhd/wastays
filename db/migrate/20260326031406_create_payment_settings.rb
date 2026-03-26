class CreatePaymentSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_settings do |t|
      t.references :settable, polymorphic: true, null: false
      t.string :gateway
      t.string :api_key
      t.string :secret_key
      t.string :webhook_secret
      t.string :status

      t.timestamps
    end
  end
end
