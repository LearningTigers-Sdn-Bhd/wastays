# frozen_string_literal: true

class CreateArPaymentVoids < ActiveRecord::Migration[8.1]
  def change
    create_table :ar_payment_voids do |t|
      t.references :ar_payment, null: false, foreign_key: true, index: { unique: true }
      t.references :voided_by, null: false, foreign_key: { to_table: :users }
      t.text :reason, null: false
      t.datetime :voided_at, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
  end
end
