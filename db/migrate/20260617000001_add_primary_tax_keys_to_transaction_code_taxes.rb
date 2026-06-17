# frozen_string_literal: true

class AddPrimaryTaxKeysToTransactionCodeTaxes < ActiveRecord::Migration[8.0]
  def change
    remove_index :transaction_code_taxes, [ :transaction_code_id, :hotel_tax_id ]

    change_column_null :transaction_code_taxes, :hotel_tax_id, true
    add_column :transaction_code_taxes, :primary_tax_key, :string

    add_index :transaction_code_taxes,
      [ :transaction_code_id, :hotel_tax_id ],
      unique: true,
      where: "hotel_tax_id IS NOT NULL",
      name: "idx_transaction_code_taxes_on_custom_tax"
    add_index :transaction_code_taxes,
      [ :transaction_code_id, :primary_tax_key ],
      unique: true,
      where: "primary_tax_key IS NOT NULL",
      name: "idx_transaction_code_taxes_on_primary_tax"
  end
end
