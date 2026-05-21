class AddAdjustmentsTotalToNightAuditFinancialSummaries < ActiveRecord::Migration[8.0]
  def change
    add_column :night_audit_financial_summaries, :adjustments_total, :decimal, precision: 15, scale: 2, default: 0.0, null: false
  end
end
