# frozen_string_literal: true

class RenameNoShowPenaltiesToNoShowCharges < ActiveRecord::Migration[7.1]
  def change
    rename_column :night_audit_financial_summaries, :no_show_penalties, :no_show_charges
  end
end
