# frozen_string_literal: true

class AddTaxRulesToTransactionCodes < ActiveRecord::Migration[8.0]
  def change
    add_column :transaction_codes, :is_taxable, :boolean, default: false, null: false

    create_table :transaction_code_taxes do |t|
      t.references :transaction_code, null: false, foreign_key: true
      t.references :hotel_tax, null: false, foreign_key: true

      t.timestamps
    end

    add_index :transaction_code_taxes, [ :transaction_code_id, :hotel_tax_id ], unique: true
  end
end
