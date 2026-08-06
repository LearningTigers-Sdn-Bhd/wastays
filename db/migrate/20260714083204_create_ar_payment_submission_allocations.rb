class CreateArPaymentSubmissionAllocations < ActiveRecord::Migration[8.0]
  def change
    create_table :ar_payment_submission_allocations do |t|
      t.references :ar_payment_submission, null: false, foreign_key: true
      t.references :ar_invoice, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.timestamps
    end

    add_index :ar_payment_submission_allocations, [ :ar_payment_submission_id, :ar_invoice_id ], unique: true, name: "index_submission_allocations_on_submission_and_invoice"
    add_check_constraint :ar_payment_submission_allocations, "amount > 0", name: "ar_payment_submission_allocations_amount_positive"

    # Superseded by the allocations join table above — a submission can now target multiple
    # invoices in one bank transfer, matching how agents actually remit (one lump sum covering
    # several invoices). No production data exists on this column yet.
    remove_reference :ar_payment_submissions, :ar_invoice, foreign_key: true
  end
end
