class HardenEInvoiceSubmissionIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_booking_and_scenario" if index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_booking_and_scenario")
    add_index :e_invoice_submissions, :fund_collector, algorithm: :concurrently
    add_index :e_invoice_submissions,
              [ :booking_id, :document_scenario ],
              unique: true,
              where: "status <> 'cancelled'",
              name: "index_e_invoice_submissions_on_active_booking_and_scenario",
              algorithm: :concurrently
  end

  def down
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_active_booking_and_scenario" if index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_active_booking_and_scenario")
    remove_index :e_invoice_submissions, :fund_collector if index_exists?(:e_invoice_submissions, :fund_collector)
    add_index :e_invoice_submissions,
              [ :booking_id, :document_scenario ],
              name: "index_e_invoice_submissions_on_booking_and_scenario" unless index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_booking_and_scenario")
  end
end
