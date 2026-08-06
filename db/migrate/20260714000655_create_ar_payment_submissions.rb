# frozen_string_literal: true

class CreateArPaymentSubmissions < ActiveRecord::Migration[8.0]
  def change
    create_table :ar_payment_submissions do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :hotel_corporate_account, null: false, foreign_key: true
      t.references :submitted_by, null: false, foreign_key: { to_table: :users }
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :currency, null: false
      t.string :reference_number, null: false
      t.date :received_at, null: false
      t.string :payment_method, default: "bank_transfer", null: false
      t.text :notes
      t.string :status, default: "pending", null: false
      t.text :rejection_reason
      t.references :ar_payment, null: true, foreign_key: true
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users }
      t.datetime :reviewed_at

      t.timestamps
    end

    add_check_constraint :ar_payment_submissions, "amount > 0", name: "ar_payment_submissions_amount_positive"
    add_check_constraint :ar_payment_submissions,
      "status IN ('pending', 'approved', 'rejected')",
      name: "ar_payment_submissions_status_allowed"
  end
end
