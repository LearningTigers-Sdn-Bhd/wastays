# frozen_string_literal: true

class AddLedgerFieldsToArInvoices < ActiveRecord::Migration[8.0]
  def change
    add_column :ar_invoices, :paid_amount, :decimal, precision: 10, scale: 2, null: false, default: 0
    add_column :ar_invoices, :outstanding_amount, :decimal, precision: 10, scale: 2, null: false, default: 0

    reversible do |dir|
      dir.up do
        execute "UPDATE ar_invoices SET outstanding_amount = amount WHERE outstanding_amount = 0"
        remove_check_constraint :ar_invoices, name: "ar_invoices_status_allowed"
      end

      dir.down do
        remove_check_constraint :ar_invoices, name: "ar_invoices_status_allowed"
      end
    end

    add_check_constraint :ar_invoices,
      "status IN ('open', 'partially_paid', 'paid', 'overdue', 'void')",
      name: "ar_invoices_status_allowed"
    add_check_constraint :ar_invoices, "paid_amount >= 0", name: "ar_invoices_paid_amount_nonnegative"
    add_check_constraint :ar_invoices, "outstanding_amount >= 0", name: "ar_invoices_outstanding_amount_nonnegative"
  end
end
