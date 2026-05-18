class CreateNightAuditFinancialSummaries < ActiveRecord::Migration[7.1]
  def change
    create_table :night_audit_financial_summaries do |t|
      t.references :night_audit, null: false, foreign_key: true, index: { unique: true }
      t.decimal :room_revenue, precision: 12, scale: 2, null: false, default: 0
      t.decimal :tax_revenue, precision: 12, scale: 2, null: false, default: 0
      t.decimal :payments_total, precision: 12, scale: 2, null: false, default: 0
      t.decimal :refunds_total, precision: 12, scale: 2, null: false, default: 0
      t.decimal :no_show_penalties, precision: 12, scale: 2, null: false, default: 0
      t.jsonb :changelog, null: false, default: []

      t.timestamps
    end
  end
end

