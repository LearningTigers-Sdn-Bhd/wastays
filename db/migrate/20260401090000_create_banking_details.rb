class CreateBankingDetails < ActiveRecord::Migration[8.0]
  def change
    create_table :banking_details do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string :account_holder_name, null: false
      t.string :bank_name, null: false
      t.string :account_number, null: false
      t.string :account_type, null: false

      t.timestamps
    end
  end
end
