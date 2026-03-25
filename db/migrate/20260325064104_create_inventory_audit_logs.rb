class CreateInventoryAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :inventory_audit_logs do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :room_type, null: true, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :action_type, null: false
      t.jsonb :old_value, null: false, default: {}
      t.jsonb :new_value, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end
