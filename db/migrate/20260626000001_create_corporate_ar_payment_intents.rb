# frozen_string_literal: true

class CreateCorporateArPaymentIntents < ActiveRecord::Migration[8.0]
  def change
    create_table :corporate_ar_payment_intents do |t|
      t.references :corporate_account, null: false, foreign_key: { to_table: :accounts }
      t.references :user, null: false, foreign_key: true
      t.references :hotel, null: false, foreign_key: true
      t.references :hotel_corporate_account, null: false, foreign_key: true
      t.references :ar_payment, null: true, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :gateway, null: false
      t.string :gateway_order_id
      t.string :external_reference
      t.string :status, null: false, default: "pending"
      t.datetime :expires_at, null: false
      t.datetime :verified_at
      t.datetime :captured_at
      t.text :error_message
      t.jsonb :invoice_snapshots, null: false, default: []
      t.jsonb :remittance_suggestions, null: false, default: []
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :corporate_ar_payment_intents, [ :corporate_account_id, :created_at ], name: "idx_corp_ar_intents_on_account_created_at"
    add_index :corporate_ar_payment_intents, [ :hotel_corporate_account_id, :status ], name: "idx_corp_ar_intents_on_relationship_status"
    add_index :corporate_ar_payment_intents, [ :gateway, :external_reference ], unique: true,
      where: "external_reference IS NOT NULL",
      name: "idx_corp_ar_intents_on_gateway_external_ref"
    add_index :corporate_ar_payment_intents, [ :gateway, :gateway_order_id ], unique: true,
      where: "gateway_order_id IS NOT NULL",
      name: "idx_corp_ar_intents_on_gateway_order"
    add_check_constraint :corporate_ar_payment_intents, "amount > 0", name: "corporate_ar_payment_intents_amount_positive"
  end
end
