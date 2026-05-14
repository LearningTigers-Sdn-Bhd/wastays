class CreateBookingAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :booking_audit_logs do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :auditable, polymorphic: true, null: false
      t.references :user, null: true, foreign_key: true
      t.string :action_type, null: false
      t.jsonb :old_value, default: {}, null: false
      t.jsonb :new_value, default: {}, null: false
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end
  end
end
