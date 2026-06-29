class ReplaceUniqueIndexOnEInvoiceSubmissions < ActiveRecord::Migration[8.0]
  def up
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_active_booking_and_scenario" if index_exists?(:e_invoice_submissions, [:booking_id, :document_scenario], unique: true)

    add_index :e_invoice_submissions, [ :booking_id, :document_scenario, :document_type ],
      unique: true,
      where: "status != 'cancelled'",
      name: "index_e_invoice_submissions_on_booking_scenario_type"
  end

  def down
    remove_index :e_invoice_submissions, name: "index_e_invoice_submissions_on_booking_scenario_type" if index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_booking_scenario_type")

    if table_exists?(:e_invoice_submissions)
      execute <<~SQL
        WITH ranked AS (
          SELECT id,
                 ROW_NUMBER() OVER (
                   PARTITION BY booking_id, document_scenario
                   ORDER BY CASE WHEN document_type = '01' THEN 0 ELSE 1 END, created_at DESC, id DESC
                 ) AS row_num
          FROM e_invoice_submissions
          WHERE status <> 'cancelled'
        )
        UPDATE e_invoice_submissions
        SET status = 'cancelled',
            updated_at = CURRENT_TIMESTAMP
        WHERE id IN (
          SELECT id
          FROM ranked
          WHERE row_num > 1
        );
      SQL

      add_index :e_invoice_submissions, [ :booking_id, :document_scenario ],
        unique: true,
        name: "index_e_invoice_submissions_on_active_booking_and_scenario" unless index_name_exists?(:e_invoice_submissions, "index_e_invoice_submissions_on_active_booking_and_scenario")
    end
  end
end
