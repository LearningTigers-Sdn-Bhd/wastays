class CreateRefundPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :refund_policies do |t|
      t.integer :min_days_before_checkin, null: false, default: 0
      t.decimal :refund_percentage, precision: 5, scale: 2, null: false, default: 100.0

      t.timestamps
    end
  end
end
