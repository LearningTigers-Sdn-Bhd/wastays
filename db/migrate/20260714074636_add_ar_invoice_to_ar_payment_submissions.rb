class AddArInvoiceToArPaymentSubmissions < ActiveRecord::Migration[8.0]
  def change
    # Nullable at the DB level so existing rows (submitted before invoice targeting was
    # required) remain valid — the model enforces presence for new submissions.
    add_reference :ar_payment_submissions, :ar_invoice, null: true, foreign_key: true
  end
end
