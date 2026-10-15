class CreateMailEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :mail_events do |t|
      t.string :mailer, null: false
      t.string :mail_action
      t.string :subject
      t.text :recipients
      t.string :status, null: false, default: "sent"
      t.text :error_message
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :mail_events, :sent_at
    add_index :mail_events, [ :status, :sent_at ]
  end
end
