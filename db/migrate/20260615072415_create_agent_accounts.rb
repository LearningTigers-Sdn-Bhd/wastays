class CreateAgentAccounts < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_accounts do |t|
      t.references :hotel, null: false, foreign_key: true
      t.string :name, null: false
      t.string :agent_code, null: false
      t.string :account_type, null: false
      t.string :contact_email
      t.string :contact_phone

      t.timestamps
    end

    add_index :agent_accounts, [ :hotel_id, :agent_code ], unique: true
  end
end
