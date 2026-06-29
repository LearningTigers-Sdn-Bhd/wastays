class AddTrackingColumnsToEInvoiceSubmissions < ActiveRecord::Migration[8.0]
  def up
    add_column :e_invoice_submissions, :requested_by_guest, :boolean, default: false, null: false
    add_column :e_invoice_submissions, :requested_at, :datetime
    add_column :e_invoice_submissions, :consolidated, :boolean, default: false, null: false
    add_column :e_invoice_submissions, :consolidation_batch_id, :uuid
    add_column :e_invoice_submissions, :payment_concluded_at, :datetime
    add_column :e_invoice_submissions, :original_invoice_internal_id, :string

    add_index :e_invoice_submissions, :consolidation_batch_id,
      name: "index_e_invoice_submissions_on_consolidation_batch_id"
    add_index :e_invoice_submissions, [ :status, :consolidated, :payment_concluded_at ],
      name: "index_e_invoice_submissions_on_status_consolidated_payment"
    add_index :e_invoice_submissions, [ :booking_id, :document_scenario, :document_type ],
      unique: true,
      where: "status != 'cancelled'",
      name: "index_e_invoice_submissions_on_booking_scenario_type_unique"
  end

  def down
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_booking_scenario_type_unique" if index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_booking_scenario_type_unique")
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_status_consolidated_payment" if index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_status_consolidated_payment")
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_consolidation_batch_id" if index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_consolidation_batch_id")

    remove_column :e_invoice_submissions, :original_invoice_internal_id if column_exists?(:e_invoice_submissions, :original_invoice_internal_id)
    remove_column :e_invoice_submissions, :payment_concluded_at if column_exists?(:e_invoice_submissions, :payment_concluded_at)
    remove_column :e_invoice_submissions, :consolidation_batch_id if column_exists?(:e_invoice_submissions, :consolidation_batch_id)
    remove_column :e_invoice_submissions, :consolidated if column_exists?(:e_invoice_submissions, :consolidated)
    remove_column :e_invoice_submissions, :requested_at if column_exists?(:e_invoice_submissions, :requested_at)
    remove_column :e_invoice_submissions, :requested_by_guest if column_exists?(:e_invoice_submissions, :requested_by_guest)
  end
end
