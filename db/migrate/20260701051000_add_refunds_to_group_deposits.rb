# frozen_string_literal: true

class AddRefundsToGroupDeposits < ActiveRecord::Migration[8.0]
  def change
    add_column :group_deposits, :refunded_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_check_constraint :group_deposits,
      "refunded_amount >= 0 AND refunded_amount <= amount",
      name: "group_deposits_refunded_amount_valid"
  end
end
