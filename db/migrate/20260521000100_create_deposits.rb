# frozen_string_literal: true

class CreateDeposits < ActiveRecord::Migration[8.0]
  def change
    create_table :deposits do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :booking, null: false, foreign_key: true
      t.references :booking_folio, null: true, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :hold_type, null: false
      t.string :status, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :currency, null: false
      t.string :payment_method
      t.string :external_reference
      t.string :gl_code
      t.datetime :collected_at
      t.datetime :authorized_at
      t.datetime :released_at
      t.datetime :forfeited_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :deposits, [ :hotel_id, :hold_type, :status ]
    add_index :deposits, :gl_code
  end
end
